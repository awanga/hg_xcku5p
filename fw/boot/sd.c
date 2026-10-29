// SPDX-License-Identifier: MIT
/*
 * SD card driver for the boot ROM: SPI mode (CMD0 .. CMD17/18) on the SiFive-style SPI master at
 * SPI_BASE. Initialisation runs at 400 kHz as the SD specification requires, then the clock is
 * raised to 25 MHz.
 */
#include <stdint.h>
#include "sd.h"

#define SPI_BASE 0xF8002000UL
#define REGS_BASE 0xF8001000UL
#define REG_TICK 0x10
#define TICK_HZ 100000000UL

#define SPI_SCKDIV 0x00
#define SPI_CSMODE 0x18
#define SPI_FMT 0x40
#define SPI_TXDATA 0x48
#define SPI_RXDATA 0x4C
#define SPI_CS_AUTO 0
#define SPI_CS_HOLD 2
#define SPI_CS_OFF 3
#define SPI_FLAG (1u << 31)

#define SCKDIV_400K 124 /* 100 MHz / (2 * 125) */
#define SCKDIV_25M 1	/* 100 MHz / 4 */

#define R1_IDLE 0x01
#define TOKEN_DATA 0xFE

static int sdhc;

static inline uint32_t rd32(uintptr_t a)
{
	return *(volatile uint32_t *)a;
}

static inline void wr32(uintptr_t a, uint32_t v)
{
	*(volatile uint32_t *)a = v;
}

static uint32_t ticks(void)
{
	return rd32(REGS_BASE + REG_TICK);
}

static uint8_t xfer(uint8_t b)
{
	uint32_t v;

	while (rd32(SPI_BASE + SPI_TXDATA) & SPI_FLAG)
		;
	wr32(SPI_BASE + SPI_TXDATA, b);
	do {
		v = rd32(SPI_BASE + SPI_RXDATA);
	} while (v & SPI_FLAG);
	return (uint8_t)v;
}

/* Send a command and return R1 (0xFF when the card does not answer). CS stays asserted. */
static uint8_t sd_cmd(uint8_t cmd, uint32_t arg, uint8_t crc)
{
	uint8_t r = 0xFF;

	xfer(0xFF);
	xfer(0x40 | cmd);
	xfer(arg >> 24);
	xfer(arg >> 16);
	xfer(arg >> 8);
	xfer(arg);
	xfer(crc);
	for (int i = 0; i < 16 && r == 0xFF; i++)
		r = xfer(0xFF);
	return r;
}

static void sd_deselect(void)
{
	wr32(SPI_BASE + SPI_CSMODE, SPI_CS_AUTO);
	xfer(0xFF);
	wr32(SPI_BASE + SPI_CSMODE, SPI_CS_HOLD);
}

int sd_init(void)
{
	uint32_t t0;
	uint8_t r;
	int v2;

	wr32(SPI_BASE + SPI_SCKDIV, SCKDIV_400K);
	wr32(SPI_BASE + SPI_FMT, 8 << 16);
	wr32(SPI_BASE + SPI_CSMODE, SPI_CS_OFF);
	for (int i = 0; i < 10; i++) /* 80 clocks with CS high */
		xfer(0xFF);
	wr32(SPI_BASE + SPI_CSMODE, SPI_CS_HOLD);

	/* A card whose multi-block read was cut off by a reset ignores CMD0 until it is stopped and drained. */
	for (int try = 0; sd_cmd(0, 0, 0x95) != R1_IDLE; try++) {
		if (try == 3)
			return -1; /* no card or not in idle state */
		sd_cmd(12, 0, 0x61);
		for (int i = 0; i < 600; i++)
			xfer(0xFF);
	}
	sdhc = 0;
	v2 = sd_cmd(8, 0x1AA, 0x87) == R1_IDLE;
	if (v2) {
		uint32_t echo = 0;

		for (int i = 0; i < 4; i++)
			echo = echo << 8 | xfer(0xFF);
		if ((echo & 0xFFF) != 0x1AA)
			return -2;
	}
	t0 = ticks();
	do {
		sd_cmd(55, 0, 0x01);
		r = sd_cmd(41, v2 ? 0x40000000 : 0, 0x01);
		if (ticks() - t0 > TICK_HZ * 2)
			return -3; /* ACMD41 timeout */
	} while (r != 0);
	if (sd_cmd(58, 0, 0x01) == 0) {
		uint32_t ocr = 0;

		for (int i = 0; i < 4; i++)
			ocr = ocr << 8 | xfer(0xFF);
		sdhc = !!(ocr & 0x40000000);
	}
	if (!sdhc && sd_cmd(16, 512, 0x01) != 0)
		return -4;
	sd_deselect();
	wr32(SPI_BASE + SPI_SCKDIV, SCKDIV_25M);
	return 0;
}

int sd_read(uint32_t lba, uint32_t count, void *dst)
{
	uint8_t *p = dst;

	if (sd_cmd(18, sdhc ? lba : lba * 512, 0x01) != 0) {
		sd_deselect();
		return -1;
	}
	for (uint32_t b = 0; b < count; b++) {
		uint32_t t0 = ticks();
		uint8_t tok;

		while ((tok = xfer(0xFF)) == 0xFF)
			if (ticks() - t0 > TICK_HZ / 2) {
				sd_deselect();
				return -2;
			}
		if (tok != TOKEN_DATA) {
			sd_deselect();
			return -3;
		}
		for (int i = 0; i < 512; i++)
			*p++ = xfer(0xFF);
		xfer(0xFF); /* CRC, not checked in SPI mode without CMD59 */
		xfer(0xFF);
	}
	sd_cmd(12, 0, 0x01);
	for (int i = 0; i < 16; i++) /* the stop command is followed by a busy phase */
		if (xfer(0xFF) == 0xFF)
			break;
	sd_deselect();
	return 0;
}

long sd_boot_load(void)
{
	static uint8_t sector[512] __attribute__((aligned(8)));
	const struct sd_boot_header *h = (const struct sd_boot_header *)sector;
	int rc;

	rc = sd_init();
	if (rc)
		return rc;
	rc = sd_read(0, 1, sector);
	if (rc)
		return -10;
	if (h->magic[0] != SD_BOOT_MAGIC0 || h->magic[1] != SD_BOOT_MAGIC1 ||
	    h->count > SD_BOOT_MAX_ENTRIES)
		return -11;
	for (uint32_t i = 0; i < h->count; i++) {
		uint32_t sectors = (h->e[i].bytes + 511) / 512;

		if (sd_read(h->e[i].lba, sectors, (void *)(uintptr_t)h->e[i].addr))
			return -12;
	}
	return (long)h->entry;
}
