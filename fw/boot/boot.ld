/* SPDX-License-Identifier: MIT */
/* Boot ROM image: code and read-only data in the 16 KiB ROM, writable data and stack in DDR4. */
MEMORY
{
	rom (rx) : ORIGIN = 0x10000000, LENGTH = 16K
	ram (rw) : ORIGIN = 0x40000000, LENGTH = 1M
}

ENTRY(_start)

SECTIONS
{
	.text : {
		*(.text.start)
		*(.text .text.*)
		*(.rodata .rodata.* .srodata .srodata.*)
	} > rom

	.bss (NOLOAD) : {
		. = ALIGN(8);
		__bss_start = .;
		*(.bss .bss.* .sbss .sbss.* COMMON)
		. = ALIGN(8);
		__bss_end = .;
	} > ram

	__stack_top = ORIGIN(ram) + LENGTH(ram);
}
