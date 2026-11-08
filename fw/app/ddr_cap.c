// SPDX-License-Identifier: MIT
/* DDR4 capacity test for the build with the 8 Gb-per-chip controller (DDR_8G, ddr_halfmap.v).
 * The DDRHALF register (0xF8001024) makes the top 256 MiB of the CPU window show either the lower
 * or the upper 1 GiB half of the controller's 2 GiB address space. Each half is filled with its
 * own hash, then both are read back:
 *  - independent halves: parts are 8 Gb per chip, 2 GiB present;
 *  - every word of one half shows the other half's hash: the upper address bit is ignored by the
 *    chips (4 Gb parts, 1 GiB present);
 *  - anything else: a failing memory or path (reported as FAIL, not a capacity answer).
 * The window moves under the data cache, so dirty lines are pushed out by touching a scratch
 * area before each switch. Run with tools/load.py fw/app/build/ddr_cap.bin. */
#include <stdint.h>

#define UART_BASE 0xF8000000UL
#define HALF_REG 0xF8001024UL
#define WIN_BASE 0x70000000UL
#define WIN_SIZE 0x10000000UL
#define SCRATCH 0x44000000UL
#define SCRATCH_SIZE 0x00100000UL

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

static const uint64_t key[2] = { 0x1111222233334444ULL, 0x5555666677778888ULL };

static void evict(void)
{
	volatile uint64_t *s = (volatile uint64_t *)SCRATCH;

	for (int pass = 0; pass < 2; pass++)
		for (uint64_t i = 0; i < SCRATCH_SIZE / 8; i += 8)
			s[i] += 1;
}

static void select_half(unsigned h)
{
	volatile uint32_t *r = (volatile uint32_t *)HALF_REG;

	evict();
	*r = h;
	while (*r != h)
		;
	for (volatile int i = 0; i < 1000; i++)
		; // two-flop synchronizer into ui_clk
}

static void fill(unsigned h)
{
	volatile uint64_t *p = (volatile uint64_t *)WIN_BASE;

	select_half(h);
	for (uint64_t i = 0; i < WIN_SIZE / 8; i++)
		p[i] = hash((uint64_t)(uintptr_t)&p[i], key[h]);
	puts_("filled half ");
	put('0' + h);
	puts_("\r\n");
}

static uint64_t words, same, other, bad;

static void check(unsigned h)
{
	volatile uint64_t *p = (volatile uint64_t *)WIN_BASE;

	select_half(h);
	for (uint64_t i = 0; i < WIN_SIZE / 8; i++) {
		uint64_t a = (uint64_t)(uintptr_t)&p[i], got = p[i];

		words++;
		if (got == hash(a, key[h]))
			same++;
		else if (got == hash(a, key[!h]))
			other++;
		else
			bad++;
	}
	puts_("checked half ");
	put('0' + h);
	puts_(" words=");
	puthex(words);
	puts_(" ok=");
	puthex(same);
	puts_(" other_half=");
	puthex(other);
	puts_(" bad=");
	puthex(bad);
	puts_("\r\n");
}

int main(void)
{
	puts_("\r\nddr_cap start\r\n");
	fill(0);
	fill(1);
	check(0);
	check(1);
	select_half(0);
	if (bad == 0 && other == 0)
		puts_("RESULT 8Gb: two independent 1 GiB halves, 2 GiB present\r\n");
	else if (bad == 0 && other == words / 2 && same == words / 2)
		puts_("RESULT 4Gb: upper half aliases the lower, 1 GiB present\r\n");
	else
		puts_("RESULT FAIL: mixed or corrupt, no capacity answer\r\n");
	return 0;
}
