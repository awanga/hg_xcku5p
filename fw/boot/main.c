// SPDX-License-Identifier: MIT
/*
 * Minimal SoC bring-up firmware, runs from the boot ROM: reports the clock and DDR4 status on the
 * UART, runs a data/address test over DDR4 and measures streaming throughput with the 100 MHz
 * peripheral tick counter, then blinks the LEDs.
 */
#include <stdint.h>

#define UART_BASE 0xF8000000UL
#define REGS_BASE 0xF8001000UL
#define DDR_BASE 0x40000000UL
#define DDR_TEST_BASE (DDR_BASE + 0x100000UL) /* above the stack/bss window */
#define TICK_HZ 100000000UL

#ifndef TEST_BYTES
#define TEST_BYTES (16UL << 20)
#endif

#define UART_RX 0x00
#define UART_TX 0x04
#define UART_STAT 0x08
#define UART_CTRL 0x0C
#define UART_STAT_TX_FULL (1u << 3)

#define REG_LED 0x00
#define REG_KEY 0x04
#define REG_STATUS 0x08
#define REG_CPU_KHZ 0x0C
#define REG_TICK 0x10

static inline uint32_t rd32(uintptr_t a)
{
	return *(volatile uint32_t *)a;
}

static inline void wr32(uintptr_t a, uint32_t v)
{
	*(volatile uint32_t *)a = v;
}

static void putc_uart(char c)
{
	while (rd32(UART_BASE + UART_STAT) & UART_STAT_TX_FULL)
		;
	wr32(UART_BASE + UART_TX, (uint32_t)c);
}

static void puts_uart(const char *s)
{
	for (; *s; s++)
		putc_uart(*s);
}

static void put_dec(uint64_t v)
{
	char buf[21];
	int n = 0;

	do {
		buf[n++] = (char)('0' + v % 10);
		v /= 10;
	} while (v);
	while (n)
		putc_uart(buf[--n]);
}

static void put_hex(uint64_t v, int digits)
{
	for (int i = digits - 1; i >= 0; i--)
		putc_uart("0123456789ABCDEF"[(v >> (4 * i)) & 0xF]);
}

static uint64_t mix(uint64_t x)
{
	x ^= x >> 33;
	x *= 0xFF51AFD7ED558CCDULL;
	x ^= x >> 33;
	return x;
}

/* Returns the number of mismatching 64-bit words; the first mismatch is reported. */
static uint64_t test_pattern(volatile uint64_t *p, uint64_t words, uint64_t seed)
{
	uint64_t errors = 0;

	for (uint64_t i = 0; i < words; i++)
		p[i] = mix(i + seed);
	__asm__ volatile("fence rw, rw");
	for (uint64_t i = 0; i < words; i++) {
		uint64_t got = p[i];

		if (got != mix(i + seed)) {
			if (!errors) {
				puts_uart("  mismatch @");
				put_hex((uintptr_t)&p[i], 8);
				puts_uart(" got ");
				put_hex(got, 16);
				puts_uart(" want ");
				put_hex(mix(i + seed), 16);
				puts_uart("\r\n");
			}
			errors++;
		}
	}
	return errors;
}

/* Address-in-address test across a span larger than the caches, one word per 4 KiB page and per 64
 * B line. */
static uint64_t test_address(volatile uint64_t *p, uint64_t words)
{
	uint64_t errors = 0;

	for (uint64_t i = 0; i < words; i += 8)
		p[i] = (uintptr_t)&p[i];
	__asm__ volatile("fence rw, rw");
	for (uint64_t i = 0; i < words; i += 8)
		if (p[i] != (uintptr_t)&p[i])
			errors++;
	return errors;
}

static void report_rate(const char *what, uint64_t bytes, uint32_t ticks)
{
	puts_uart(what);
	puts_uart(": ");
	put_dec(bytes * (TICK_HZ / 1000000) / ticks); /* bytes per microsecond = MB/s */
	puts_uart(" MB/s\r\n");
}

static void bandwidth(volatile uint64_t *p, uint64_t words)
{
	uint32_t t0, t1;
	uint64_t sum = 0;

	t0 = rd32(REGS_BASE + REG_TICK);
	for (uint64_t i = 0; i < words; i++)
		p[i] = i;
	__asm__ volatile("fence rw, rw");
	t1 = rd32(REGS_BASE + REG_TICK);
	report_rate("  write", words * 8, t1 - t0);

	t0 = rd32(REGS_BASE + REG_TICK);
	for (uint64_t i = 0; i < words; i++)
		sum += p[i];
	t1 = rd32(REGS_BASE + REG_TICK);
	report_rate("  read ", words * 8, t1 - t0);
	if (sum != words * (words - 1) / 2)
		puts_uart("  bandwidth read-back mismatch\r\n");
}

int main(void)
{
	volatile uint64_t *test = (volatile uint64_t *)DDR_TEST_BASE;
	const uint64_t words = TEST_BYTES / 8;
	uint32_t status;
	uint64_t pass = 0;

	wr32(UART_BASE + UART_CTRL, 0x3); /* reset FIFOs */
	puts_uart("\r\nHG-XCKU5P minimal SoC\r\n");
	puts_uart("CPU clock: ");
	put_dec(rd32(REGS_BASE + REG_CPU_KHZ));
	puts_uart(" kHz\r\n");
	status = rd32(REGS_BASE + REG_STATUS);
	puts_uart("DDR4 calibrated: ");
	put_dec(status & 1);
	puts_uart("\r\n");

	for (;;) {
		uint64_t errs = 0;

		puts_uart("pass ");
		put_dec(pass);
		puts_uart("\r\n");
		errs += test_pattern(test, words, pass * 0x9E3779B97F4A7C15ULL);
		errs += test_address(test, words);
		puts_uart("  errors: ");
		put_dec(errs);
		puts_uart("\r\n");
		bandwidth(test, words);
		wr32(REGS_BASE + REG_LED, (errs ? 0x80 : 0x00) | (uint32_t)(pass & 0x7F));
		pass++;
	}
}
