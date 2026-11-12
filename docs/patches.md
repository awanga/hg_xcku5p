# Local patches and upstream disposition

Reviewed 2026-11-12. Every external source is used at an upstream commit (docs/versions.md); this lists what is changed locally.

| Item | Base | Purpose | Test | Upstream status |
|---|---|---|---|---|
| Linux kernel | v6.18.59, unpatched | none: configuration only (`linux/kernel/configure.sh`: tinyconfig base plus the drivers listed in the script) | boots on the board (docs/validation/linux-bringup.md) | not applicable, no patches |
| OpenSBI | v1.9, unpatched | built with the generic platform and fixed addresses (`linux/build_sd.sh`) | boots on the board | not applicable |
| Buildroot | 2026.02.3, unpatched | `linux/buildroot/hg_xcku5p_defconfig` and `post-build.sh` (devtmpfs, read-only root, persistent /data, init scripts) | image boots | not applicable (board config only) |
| Device tree | v6.18 bindings | `linux/dts/hg-xcku5p.dtsi`: CLINT, PLIC, UART lite, SiFive SPI, AXI GPIO/timer, LiteEth, w1-gpio, gpio-beeper, pwm-fan, mmc-spi, MS5607. Only existing bindings are used, except the board and CPU compatibles (`hamgeek,hg-xcku5p`, `spinalhdl,vexiiriscv`), which have no binding | `tests/dts/run.sh` (dtc, address map, mutant); board boot. `dtbs_check` has not been run | a board DTS could go upstream only with a vendor binding for the compatibles; not planned (personal platform) |
| VexiiRiscv | commit 0dc189e (docs/versions.md) | `fpga/patches/vexii-l2-blackbox.patch`: emits the L2 data banks as a black-box module so they map to UltraRAM (`fpga/scripts/cpu/uram_l2.sh`) | `tests/soc/run.sh` (Verilator, L2 netlist) and the board | not submitted; a configurable memory-primitive hook would be the upstreamable form (open) |
| LiteEth / LiteX | commits in docs/versions.md | unpatched; pinned to master for a CRC checker fix (no release contains it) | `tests/rtl/run_liteeth.sh`, board Ethernet | move to the first release that contains the fix |

Owner of every item above: the project owner. There are no local kernel patches, so no kernel upstreaming work is pending.
