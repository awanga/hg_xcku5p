// SPDX-License-Identifier: MIT
/* Smallest loadable program: prints a line and returns to the boot ROM loader. Used by tests/soc to exercise the loader. */
#include <stdint.h>

#define UART_BASE 0xF8000000UL
#define UART_TX 0x04
#define UART_STAT 0x08
#define UART_STAT_TX_FULL (1u << 3)

int main(void)
{
	static const char msg[] = "HELLO FROM APP\r\n";

	for (const char *p = msg; *p; p++) {
		while (*(volatile uint32_t *)(UART_BASE + UART_STAT) & UART_STAT_TX_FULL)
			;
		*(volatile uint32_t *)(UART_BASE + UART_TX) = (uint32_t)*p;
	}
	return 0;
}
