/* SPDX-License-Identifier: MIT */
/* Programs loaded into DDR4 by the boot ROM loader: code at 0x40100000, stack at the top of a 16 MiB window. */
MEMORY
{
	ram (rwx) : ORIGIN = 0x40100000, LENGTH = 16M
}

ENTRY(_start)

SECTIONS
{
	.text : {
		*(.text.start)
		*(.text .text.*)
		*(.rodata .rodata.* .srodata .srodata.*)
	} > ram

	.data : {
		*(.data .data.* .sdata .sdata.*)
	} > ram

	.bss (NOLOAD) : {
		. = ALIGN(8);
		__bss_start = .;
		*(.bss .bss.* .sbss .sbss.* COMMON)
		. = ALIGN(8);
		__bss_end = .;
	} > ram

	__stack_top = ORIGIN(ram) + LENGTH(ram);
}
