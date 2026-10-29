# Linux bring-up (2026-10-29)

Evidence: **board**. Hardware: `build/soc/vv_333c` (soc_base: non-coherent VexiiRiscv RV64IMA, no L2, CPU and DDR4-2667 controller on one 333.33 MHz clock;
timing met, WNS +0.010 ns), loaded with `openFPGALoader --cable ft232`.

## Software (pins in docs/versions.md)
- Linux v6.18.59 (LTS), OpenSBI v1.9 generic platform, Buildroot 2026.02.3 (musl, busybox 1.37.0), all RV64IMA (no C/F/D: the core has neither).
- Buildroot: `linux/buildroot/hg_xcku5p_defconfig` + `post-build.sh` (mounts devtmpfs first; the kernel does not do it for an initramfs root).
  Build: `make O=build/linux/br BR2_DEFCONFIG=linux/buildroot/hg_xcku5p_defconfig defconfig` in the Buildroot tree, then `make -j8` in `build/linux/br`.
- Kernel: `linux/kernel/configure.sh <linux-src> <out> <cross-prefix> <rootfs.cpio>` (tinyconfig base, NONPORTABLE so EFI/RISCV_ISA_C stay off,
  UART lite console, embedded initramfs), then `make ARCH=riscv CROSS_COMPILE=... O=<out> Image` (4.75 MB with the 2 MB rootfs).
- OpenSBI: `make PLATFORM=generic PLATFORM_RISCV_XLEN=64 PLATFORM_RISCV_ISA=rv64ima_zicsr_zifencei PLATFORM_RISCV_ABI=lp64 FW_TEXT_START=0x40100000 FW_JUMP_ADDR=0x40200000 FW_JUMP_FDT_ADDR=0x41f00000 FW_FDT_PATH=<dtb>` with the Buildroot cross compiler (the bare-metal xPack GCC cannot link PIE).
- Device tree: `linux/dts/hg-xcku5p.dts` (CLINT, PLIC, UART lite at 0xF8000000 IRQ 1, 1 GiB at 0x40000000, timebase 333333333).

## Boot procedure
```
openFPGALoader --cable ft232 build/soc/vv_333c/soc.bit
python3 tools/load.py --listen 70 fw_jump.bin@0x40100000 Image@0x40200000 hg-xcku5p.dtb@0x41f00000 --run 0x40100000
```
Loading 5.3 MB over the 230400 baud UART loader takes about 4.5 minutes (the AMD UART lite tops out at 230400).

## Result
OpenSBI banner (aclint-mtimer @ 333333333 Hz, xlnx-uartlite console), kernel boots (Sv39, 1 GiB, PLIC and timer interrupts working,
`riscv-timer` and `uartlite` IRQs counted in /proc/interrupts), busybox init reaches a login prompt on ttyUL0; `uname`, `/proc/cpuinfo`
(rv64ima_zicntr_zicsr_zifencei_zaamo_zalrsc, mmu sv39), `free` (1027268 kB total) and shell loops work.
Shell-loop speed: 20000 iterations of a busybox `$((i+1))` loop in 2.75 s (an unoptimised data point, not a benchmark).

## Known issues / not done
- `Starting network ... FAIL`: kernel built with CONFIG_NET=n (expected until Ethernet).
- No persistent storage yet (initramfs only); no SD, Ethernet or PCIe drivers; the LiteEth/MAC choice is still open.
- Boot needs the host to push the images each time (no flash/SD boot yet).
- One run, room temperature; no soak test. The 333 MHz timing margin is 10 ps.
