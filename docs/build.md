# Building the platform from a clean checkout

Reviewed 2026-11-13. Evidence of each step is in `docs/validation/`; the pins are in `docs/versions.md`. Everything lands in the gitignored `build/`.

## Host prerequisites
Linux x86-64; AMD Vivado 2026.1 (with the xcku5p device and a licence that covers DDR4 and the other IP used: `scripts/check-env.sh`); a JDK (21) and sbt for the CPU generator; xPack riscv-none-elf-gcc 15.2
(boot ROM, firmware); Python 3 with pyserial; dtc, cpp, e2fsprogs, verilator, iverilog, yosys and sby for the tests; openFPGALoader for JTAG/flash.
Tools are installed under `build/tools/` (the paths used by the scripts: `build/tools/sbt`, `build/tools/xpack-riscv-none-elf-gcc-15.2.0-1`, `build/tools/litex-venv`).

## Steps
1. `scripts/fetch_sources.sh` — fetches VexiiRiscv, Linux, OpenSBI, Buildroot, LiteEth, LiteX at the pinned commits and applies the local patches (`fpga/patches`, `linux/patches`).
2. `fpga/scripts/gen_liteeth.sh` — LiteEth core Verilog (`build/liteeth`); the one-time LiteX venv setup is described in its header.
3. `fpga/scripts/cpu/gen_default_soc.sh` — the VexiiRiscv SoC netlist `soc_l2u_128k_w4` (sbt; also builds the UltraRAM L2 black box).
4. `make -C fw/boot BUILD=build_sd` — boot ROM image `fw/boot/build_sd/boot_rom.hex` (copy to `build/boot_rom_sd.hex`).
5. `vivado -mode batch -source fpga/scripts/build_soc.tcl -tclargs build/soc/<name> soc_l2u_128k_w4 750 build/boot_rom_sd.hex -strategy Performance_ExplorePostRoutePhysOpt`; if the report shows a small negative slack,
   `fpga/scripts/postroute_fix.tcl` on the routed checkpoint. `tools/build_report.py` output (`report.json`) must show WNS and WHS >= 0 and no DRC errors.
6. Flash-ready bitstream: `fpga/scripts/flash_bit.tcl <routed.dcp> <out.bit>`; program with `openFPGALoader --cable ft232 --freq 3000000 --fpga-part xcku5p-ffvb676 -f --verify --unprotect-flash <out.bit>`
   (details and recovery: `docs/validation/flash-boot.md`, `factory/`).
7. Linux: `make -C build/third_party/buildroot O=$PWD/build/linux/br BR2_DEFCONFIG=$PWD/linux/buildroot/hg_xcku5p_defconfig defconfig`, then `make -C build/third_party/buildroot O=$PWD/build/linux/br`;
   `linux/build_sd.sh` builds the kernel, device tree, OpenSBI and `build/linux/sdcard.img` (the owner writes it with `dd`; it holds /data, so `build/linux/boot_area.img`, the first 16 MiB, updates the
   boot files only).
8. Check: `tools/smoke.py --reset flash --sd --net <host>` (19 checks), `scripts/ci.sh` (host checks), `tests/dts/dtbs_check.sh` (binding schemas), `scripts/legal_info.sh` (licence manifest).
9. Release: `scripts/release.sh <version> <flash-ready.bit>`.

Known gaps: a repeat of steps 2-3 and 5 from an empty tree was not done (the sbt netlist generation and a full Vivado run take hours; step 1 and `scripts/ci.sh` were repeated in a fresh clone, see TASKS.md).
Bitstreams are not bit-reproducible across Vivado runs by contract; the reference is the `report.json` timing result plus the smoke test.
