#!/bin/bash
# SPDX-License-Identifier: MIT
# Configure the Linux kernel for the HG-XCKU5P SoC (RV64IMA, no C/F/D, one hart, UART lite console, embedded initramfs).
# usage: configure.sh <linux-src> <out-dir> <cross-prefix> <rootfs.cpio | ''>   (empty: no initramfs, root on the SD card)
# tinyconfig base keeps the Image small (it is loaded over a 230400 baud UART).
# NONPORTABLE is needed: PORTABLE selects EFI, which selects RISCV_ISA_C. EFI and ISA_C are cleared in a second pass.
set -eu
src=$1 out=$2 cross=$3 cpio=$4
mkdir -p "$out"
cd "$src"
make ARCH=riscv CROSS_COMPILE="$cross" O="$out" tinyconfig >/dev/null
./scripts/config --file "$out/.config" -e 64BIT -e MMU -e NONPORTABLE -d FPU -d SMP \
	-e PRINTK -e PRINTK_TIME -e TTY -e SERIAL_CORE -e SERIAL_UARTLITE -e SERIAL_UARTLITE_CONSOLE --set-val SERIAL_UARTLITE_NR_UARTS 1 \
	-e SERIAL_EARLYCON -e SERIAL_EARLYCON_RISCV_SBI -e BLK_DEV_INITRD --set-str INITRAMFS_SOURCE "$cpio" -e INITRAMFS_COMPRESSION_NONE \
	-e PROC_FS -e SYSFS -e DEVTMPFS -e DEVTMPFS_MOUNT -e TMPFS -e BINFMT_ELF -e BINFMT_SCRIPT -e UNIX98_PTYS -e RISCV_SBI -e SOC_VIRT -e OF \
	-e BLOCK -e MSDOS_PARTITION -e MULTIUSER -e SPI -e SPI_SIFIVE -e MMC -e MMC_BLOCK -e MMC_SPI -e EXT4_FS -e CRC7 -e CRC_ITU_T -e FUTEX -e EPOLL -e EVENTFD -e SIGNALFD -e TIMERFD -e SHMEM -e POSIX_TIMERS -e RISCV_TIMER -e CLINT_TIMER \
	-e SIFIVE_PLIC -e HIGH_RES_TIMERS -e NO_HZ_IDLE -e CMDLINE_FROM_DTB
make ARCH=riscv CROSS_COMPILE="$cross" O="$out" olddefconfig >/dev/null
./scripts/config --file "$out/.config" -d EFI -d RISCV_ISA_C
make ARCH=riscv CROSS_COMPILE="$cross" O="$out" olddefconfig >/dev/null
if grep -q '^CONFIG_RISCV_ISA_C=y' "$out/.config"; then echo "RISCV_ISA_C still enabled" >&2; exit 1; fi
