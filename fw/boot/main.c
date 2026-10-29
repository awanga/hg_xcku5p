// SPDX-License-Identifier: MIT
/*
 * Boot ROM monitor: reports the clock and DDR4 status on the UART, runs TEST_PASSES data/address
 * test passes over DDR4 with streaming throughput (100 MHz peripheral tick counter), then serves a
 * loader protocol on the UART (tools/load.py):
 *   "W <hex addr> <hex len>\n" + len raw bytes  ->  "OK <hex byte sum>\n"
 *   "G <hex addr>\n"                            ->  "GO\n", fence.i, jump
 *   "T\n"                                       ->  one more test pass
 * A loaded program that returns lands back here through crt0.
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
#ifndef TEST_PASSES
#define TEST_PASSES 1
#endif

#define UART_RX 0x00
#define UART_TX 0x04
#define UART_STAT 0x08
#define UART_CTRL 0x0C
#define UART_STAT_RX_VALID (1u << 0)
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

static char getc_uart(void)
{
	while (!(rd32(UART_BASE + UART_STAT) & UART_STAT_RX_VALID))
		;
	return (char)rd32(UART_BASE + UART_RX);
}

static uint64_t parse_hex(char *c)
{
	uint64_t v = 0;

	for (;;) {
		*c = getc_uart();
		if (*c >= '0' && *c <= '9')
			v = v << 4 | (uint64_t)(*c - '0');
		else if (*c >= 'a' && *c <= 'f')
			v = v << 4 | (uint64_t)(*c - 'a' + 10);
		else if (*c >= 'A' && *c <= 'F')
			v = v << 4 | (uint64_t)(*c - 'A' + 10);
		else
			return v;
	}
}

static uint64_t run_pass(uint64_t pass)
{
	volatile uint64_t *test = (volatile uint64_t *)DDR_TEST_BASE;
	const uint64_t words = TEST_BYTES / 8;
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
	return errs;
}

int main(void)
{
	uint64_t pass = 0;

	wr32(UART_BASE + UART_CTRL, 0x2); /* reset the RX FIFO only: a returning program may still be draining TX */
	puts_uart("\r\nHG-XCKU5P minimal SoC\r\n");
	puts_uart("CPU clock: ");
	put_dec(rd32(REGS_BASE + REG_CPU_KHZ));
	puts_uart(" kHz\r\n");
	puts_uart("DDR4 calibrated: ");
	put_dec(rd32(REGS_BASE + REG_STATUS) & 1);
	puts_uart("\r\n");

	for (; pass < TEST_PASSES; pass++)
		run_pass(pass);

	for (;;) {
		char c;
		uint64_t addr, len, sum = 0;

		puts_uart("> ");
		c = getc_uart();
		if (c == 'T') {
			run_pass(pass++);
		} else if (c == 'W') {
			volatile uint8_t *p;

			getc_uart(); /* space */
			addr = parse_hex(&c);
			len = parse_hex(&c);
			p = (volatile uint8_t *)addr;
			for (uint64_t i = 0; i < len; i++) {
				uint8_t b = (uint8_t)getc_uart();

				p[i] = b;
				sum += b;
			}
			__asm__ volatile("fence rw, rw");
			puts_uart("OK ");
			put_hex(sum, 8);
			puts_uart("\r\n");
		} else if (c == 'G') {
			getc_uart(); /* space */
			addr = parse_hex(&c);
			puts_uart("GO\r\n");
			__asm__ volatile("fence rw, rw; fence.i");
			((void (*)(void))addr)();
		}
	}
}
