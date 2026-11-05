// SPDX-License-Identifier: MIT
/* UART TX integrity probe. Sends numbered lines so the host can see dropped or repeated characters, in four modes:
 * A polled TX_FULL like OpenSBI, B the same with fences around every access, C unchecked back-to-back writes that
 * reveal the FIFO depth the CPU sees, D paced writes (control). Run with tools/load.py, check with tools/uart_burst_check.py. */
#include <stdint.h>

#define UART_BASE 0xF8000000UL
#define UART_TX 0x04
#define UART_STAT 0x08
#define UART_STAT_TX_EMPTY (1u << 2)
#define UART_STAT_TX_FULL (1u << 3)

#define LINES 60
#define FILL 70

static inline uint32_t rd(uintptr_t off)
{
	return *(volatile uint32_t *)(UART_BASE + off);
}

static inline void wr(uintptr_t off, uint32_t v)
{
	*(volatile uint32_t *)(UART_BASE + off) = v;
}

static inline void fence(void)
{
	__asm__ volatile("fence iorw, iorw" ::: "memory");
}

static void put_polled(char c)
{
	while (rd(UART_STAT) & UART_STAT_TX_FULL)
		;
	wr(UART_TX, (uint32_t)c);
}

static void put_fenced(char c)
{
	for (;;) {
		fence();
		if (!(rd(UART_STAT) & UART_STAT_TX_FULL))
			break;
	}
	fence();
	wr(UART_TX, (uint32_t)c);
	fence();
}

static void put_byte(char c)
{
	while (*(volatile uint8_t *)(UART_BASE + UART_STAT) & UART_STAT_TX_FULL)
		;
	*(volatile uint8_t *)(UART_BASE + UART_TX) = (uint8_t)c;
}

static void wait_empty(void)
{
	while (!(rd(UART_STAT) & UART_STAT_TX_EMPTY))
		;
	for (volatile int i = 0; i < 200000; i++)
		;
}

static void num(void (*put)(char), unsigned int v, int digits)
{
	for (int d = digits - 1; d >= 0; d--) {
		unsigned int p = 1;

		for (int k = 0; k < d; k++)
			p *= 10;
		put((char)('0' + (v / p) % 10));
	}
}

static void str(void (*put)(char), const char *s)
{
	while (*s)
		put(*s++);
}

static void lines(void (*put)(char), char tag)
{
	for (unsigned int n = 0; n < LINES; n++) {
		put(tag);
		num(put, n, 3);
		put(' ');
		for (unsigned int i = 0; i < FILL; i++)
			put((char)('a' + (n + i) % 26));
		str(put, "\r\n");
	}
}

static void put_paced(char c)
{
	put_polled(c);
	for (volatile int i = 0; i < 400; i++)
		;
}

int main(void)
{
	unsigned int full_at = 0;
	uint32_t st[48];
	uint32_t stat_after;

	str(put_polled, "\r\n==BURST START\r\n");
	lines(put_polled, 'A');
	wait_empty();
	lines(put_fenced, 'B');
	wait_empty();
	lines(put_byte, 'F');
	wait_empty();

	str(put_polled, "C:");
	wait_empty();
	for (unsigned int i = 0; i < 48; i++) {
		wr(UART_TX, (uint32_t)('A' + i % 26));
		st[i] = rd(UART_STAT);
	}
	for (volatile int i = 0; i < 20000000; i++)
		;
	stat_after = rd(UART_STAT);
	for (unsigned int i = 0; i < 48 && !full_at; i++)
		if (st[i] & UART_STAT_TX_FULL)
			full_at = i + 1;
	str(put_polled, "\r\nC full_at=");
	num(put_polled, full_at, 2);
	str(put_polled, " (48 chars written) stat_after=");
	num(put_polled, stat_after & 0xff, 3);
	str(put_polled, "\r\n");

	lines(put_paced, 'D');
	for (int r = 0; r < 10; r++)
		lines(put_polled, 'E');
	str(put_polled, "==BURST END\r\n");
	return 0;
}
