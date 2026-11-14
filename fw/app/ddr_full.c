// SPDX-License-Identifier: MIT
/* Whole-window DDR4 test: checks that every address in the 1 GiB window is a distinct, working
 * location.
 * 1. Address-line test: a unique word at the window base and at base + 2^k for every k, read back
 * after all writes (an alias or a stuck address line makes two of them collide).
 * 2. Full sweep, two passes: each 64-bit word holds hash(address, pass key); pass 1 is written then
 * read, pass 2 uses the inverted key. The first 32 MiB (this program, its stack, the loader) is
 * skipped. Run with tools/load.py fw/app/build/ddr_full.bin; the result is one line "RESULT ...
 * PASS|FAIL" on the UART. */
#include <stdint.h>

#define UART_BASE 0xF8000000UL
#define DDR_BASE 0x40000000UL
#define DDR_SIZE 0x40000000UL
#define SKIP 0x02000000UL

static void put(char c)
{
	while (*(volatile uint32_t *)(UART_BASE + 0x08) & (1u << 3))
		;
	*(volatile uint32_t *)(UART_BASE + 0x04) = (uint32_t)c;
}

static void puts_(const char *s)
{
	while (*s)
		put(*s++);
}

static void puthex(uint64_t v)
{
	for (int i = 60; i >= 0; i -= 4)
		put("0123456789abcdef"[(v >> i) & 15]);
}

static uint64_t hash(uint64_t a, uint64_t key)
{
	uint64_t x = (a >> 3) ^ key;

	x ^= x >> 31;
	x *= 0x9E3779B97F4A7C15ULL;
	x ^= x >> 29;
	x *= 0xBF58476D1CE4E5B9ULL;
	return x ^ (x >> 32);
}

static uint64_t errors;
static unsigned shown;

static void fail(uint64_t addr, uint64_t got, uint64_t want)
{
	errors++;
	if (shown++ < 8) {
		puts_("ERR addr=");
		puthex(addr);
		puts_(" got=");
		puthex(got);
		puts_(" want=");
		puthex(want);
		puts_("\r\n");
	}
}

static void sweep(uint64_t key, const char *name)
{
	volatile uint64_t *p = (volatile uint64_t *)(DDR_BASE + SKIP);
	uint64_t n = (DDR_SIZE - SKIP) / 8, i;

	for (i = 0; i < n; i++)
		p[i] = hash((uint64_t)(uintptr_t)&p[i], key);
	for (i = 0; i < n; i++) {
		uint64_t want = hash((uint64_t)(uintptr_t)&p[i], key), got = p[i];

		if (got != want)
			fail((uint64_t)(uintptr_t)&p[i], got, want);
	}
	puts_("PASSDONE ");
	puts_(name);
	puts_(" errors=");
	puthex(errors);
	puts_("\r\n");
}

int main(void)
{
	uint64_t k, a;

	puts_("\r\nddr_full start\r\n");
	*(volatile uint64_t *)DDR_BASE = hash(DDR_BASE, 7);
	for (k = 5; k < 30; k++) {
		a = DDR_BASE + (1UL << k);
		*(volatile uint64_t *)a = hash(a, 7);
	}
	for (k = 5; k < 30; k++) {
		a = DDR_BASE + (1UL << k);
		if (*(volatile uint64_t *)a != hash(a, 7))
			fail(a, *(volatile uint64_t *)a, hash(a, 7));
	}
	if (*(volatile uint64_t *)DDR_BASE != hash(DDR_BASE, 7))
		fail(DDR_BASE, *(volatile uint64_t *)DDR_BASE, hash(DDR_BASE, 7));
	puts_("PASSDONE addrlines errors=");
	puthex(errors);
	puts_("\r\n");
	sweep(0x1234567890ABCDEFULL, "sweep1");
	sweep(~0x1234567890ABCDEFULL, "sweep2");
	puts_(errors ? "RESULT FAIL errors=" : "RESULT PASS errors=");
	puthex(errors);
	puts_("\r\n");
	return 0;
}
