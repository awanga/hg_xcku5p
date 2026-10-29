/* SPDX-License-Identifier: MIT */
/* Start-up shared by the boot ROM (resets into the loader) and loaded programs (return to the ROM loader). */
	.section .text.start
	.globl _start
_start:
	csrw	mie, zero
	la	sp, __stack_top
	la	t0, __bss_start
	la	t1, __bss_end
1:	bgeu	t0, t1, 2f
	sd	zero, 0(t0)
	addi	t0, t0, 8
	j	1b
2:	call	main
	/* let the UART transmit FIFO drain: the ROM resets the FIFOs when it restarts */
	li	t1, 0xF8000000
3:	lw	t2, 8(t1)
	andi	t2, t2, 4
	beqz	t2, 3b
	li	t0, 0x10000000
	jr	t0
