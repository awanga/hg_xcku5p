// SPDX-License-Identifier: MIT
/*
 * Working-set sweep for the L2 cache study, runs from the boot ROM on the minimal SoC (simulation
 * and board). Per working-set size it prints core cycles (rdcycle) per 64 B line for sequential
 * read, dependent random loads (pointer chase) and copy:  "MB <bytes> seq <x100> chase <x100> copy
 * <x100>"
 */
#include <stdint.h>

#define UART_BASE 0xF8000000UL
#define UART_TX 0x04
#define UART_STAT 0x08
#define UART_STAT_TX_FULL (1u << 3)
#define DDR_BASE 0x40100000UL
#define LINE 64UL

#ifndef SIZES
#define SIZES 16384, 65536, 262144, 524288, 1048576, 2097152, 4194304
#endif
#ifndef MAX_BYTES
#define MAX_BYTES (4UL << 20)
#endif

static inline uint64_t cycles(void)
{
	uint64_t c;

	__asm__ volatile("rdcycle %0" : "=r"(c));
	return c;
}

static void putc_uart(char c)
{
	while (*(volatile uint32_t *)(UART_BASE + UART_STAT) & UART_STAT_TX_FULL)
		;
	*(volatile uint32_t *)(UART_BASE + UART_TX) = (uint32_t)c;
}

static void puts_uart(const char *s)
{
	for (; *s; s++)
		putc_uart(*s);
}

static void put_dec(uint64_t v)
{
	char b[21];
	int n = 0;

	do {
		b[n++] = (char)('0' + v % 10);
		v /= 10;
	} while (v);
	while (n)
		putc_uart(b[--n]);
}

static uint64_t xs;

static uint64_t rnd(void)
{
	xs ^= xs << 13;
	xs ^= xs >> 7;
	xs ^= xs << 17;
	return xs;
}

int main(void)
{
	static const uint64_t sizes[] = {SIZES};
	volatile uint64_t *a = (volatile uint64_t *)DDR_BASE;
	volatile uint64_t *b = (volatile uint64_t *)(DDR_BASE + MAX_BYTES);

	xs = 0x2545F4914F6CDD1DULL;

	for (unsigned int k = 0; k < sizeof(sizes) / sizeof(sizes[0]); k++) {
		uint64_t bytes = sizes[k];
		uint64_t lines = bytes / LINE;
		uint64_t words = bytes / 8;
		/* two passes when the set can be cached, so the measured pass starts warm */
		uint64_t reps = bytes >= (1UL << 20) ? 1 : 2;
		uint64_t sum = 0, p = 0, t0, t_seq, t_chase, t_copy;

		/* random cyclic permutation over the lines (Sattolo), index stored in word 0 of
		 * each line */
		for (uint64_t i = 0; i < lines; i++)
			a[i * 8] = i;
		for (uint64_t i = lines - 1; i > 0; i--) {
			uint64_t j = rnd() % i;
			uint64_t t = a[i * 8];

			a[i * 8] = a[j * 8];
			a[j * 8] = t;
		}
		for (uint64_t i = 0; i < words; i++)
			sum += a[i];

		t0 = cycles();
		for (uint64_t r = 0; r < reps; r++)
			for (uint64_t i = 0; i < words; i += 8)
				sum += a[i] + a[i + 1] + a[i + 2] + a[i + 3] + a[i + 4] + a[i + 5] +
				       a[i + 6] + a[i + 7];
		t_seq = cycles() - t0;

		t0 = cycles();
		for (uint64_t s = 0; s < lines * reps; s++)
			p = a[p * 8];
		t_chase = cycles() - t0;

		t0 = cycles();
		for (uint64_t r = 0; r < reps; r++)
			for (uint64_t i = 0; i < words; i++)
				b[i] = a[i];
		t_copy = cycles() - t0;

		puts_uart("MB ");
		put_dec(bytes);
		puts_uart(" seq ");
		put_dec(t_seq * 100 / (lines * reps));
		puts_uart(" chase ");
		put_dec(t_chase * 100 / (lines * reps));
		puts_uart(" copy ");
		put_dec(t_copy * 100 / (lines * reps));
		puts_uart(" chk ");
		put_dec((sum + p) & 1);
		puts_uart("\r\n");
	}
	puts_uart("DONE\r\n");
	for (;;)
		;
}
