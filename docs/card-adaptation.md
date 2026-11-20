# Adapting the CPU-less PCIe card build (`-card`) to a new function block

The `-card` build is DDR4, the PCIe Gen3 x4 endpoint, the UART2 test rig and a reference function block (`fpga/rtl/user_ip.v`), with none of the board peripherals. It is the starting point for putting another IP (for example OpenMLA) on this board. Details of each part: `docs/validation/pcie-only.md` ("Lean card", "Adapting the card build"); identity and flash boot: `docs/validation/pcie-flash-enumeration.md`.

## What the new IP gets
| Connection | Where | Notes |
|---|---|---|
| Registers | `user_ip` AXI4-Lite window, 16 KiB at BAR0 + 0x4000 (rig 0xF8004000), 100 MHz `per_clk` | map in the header of `user_ip.v`; `user_regs` (BAR0 + 0x2000) offers 16 control and 16 status words, kick pulses and an event/interrupt-enable word |
| Interrupts | `irq[UIRQ-1:0]` levels, `-uirq N` (1..6, default 6) | MSI/INTx vectors 2..7; one message per assertion (`irq_req.v`) |
| DDR4 | `UMEM` AXI4 master ports, `-umem N` (default 2, 14 close timing) | 256-bit, 32-bit address, 4-bit ids, 333 MHz `ui_clk`, shared with the rig and the PCIe DMA |
| Bulk data from the host | XDMA H2C/C2H through the DMA window of `pcie_regs` (BAR0 + 0xA070/0xA074) into DDR4 | the window is closed at reset |

## Steps
1. **Identity**: edit `fpga/pcie_identity.cfg` (vendor, device, subsystem IDs, class, revision). `build_soc.tcl` applies it to the XDMA core, reads it back, and fails the build if the generated `PF0_*` parameters differ. The same values are in `card_regs` for the board smoke test. The flash image is the identity; there is no EEPROM on the edge connector.
2. **The block**: replace the body of `user_ip.v` (or add your module and instantiate it from it), keeping the ports. Put new files in the card file list in `fpga/scripts/build_soc.tcl` (the `if {$card}` branch that adds `card_top.v`, `user_ip.v`, `mem_probe.v`). Keep `mem_probe` while you bring the block up: it checks each DDR4 port independently of your logic. Vendor IP the block needs is created in the same script next to `xbar_mem`.
3. **Ports and lines**: `-umem N` and `-uirq N` on the `build_soc.tcl` command line set both the crossbar and the `card_top` parameters.
4. **Clocks**: the register side is `per_clk` (100 MHz), the memory side `ui_clk` (333 MHz). Anything crossing between them needs a synchroniser in RTL and a constraint in `fpga/constraints/card_board.xdc` (see the `u_probe` and `irq` lines). The XDC reader here does not accept Tcl control flow.
5. **Tests** (`tests/rtl/run.sh`): copy the pattern of `tests/rtl/tb_uip.v` (Icarus and Verilator, an AXI4 slave model that checks bursts, independent expected values) and commit mutants for the new logic. A change to `pcie_ep.v` also needs the xsim root-port tests (`tests/pcie/run_sim.sh`).
6. **Build**: `vivado -mode batch -nojournal -log build/soc/<name>.log -source fpga/scripts/build_soc.tcl -tclargs build/soc/<name> nocpu 750 build/boot_rom_sd.hex -card [-umem N] [-uirq N] -strategy Performance_ExtraTimingOpt`. Run one build at a time (parallel builds ran out of memory on this 32 GB host).
7. **Board** (JTAG, flash untouched): `python3 tools/card_smoke.py --reset build/soc/<name>/soc.bit --umem N` (identity, registers, user window, interrupts as far as no link allows, every DDR4 port, rig access). Extend it with checks for the new block.
8. **Flash image** (the card enumerates from flash, with the configuration-time limits in `pcie-flash-enumeration.md`): `scripts/card_flash_image.sh <routed.dcp> <out.bit>` makes the image and prints the write command; writing the flash needs the owner's approval.
9. **Host**: after a flash boot, `python3 tools/pcie_identity.py host-check <BDF>` and `check-lspci` compare what the host sees with the manifest. If the card is missing after power-up, `echo 1 | sudo tee /sys/bus/pci/rescan` (the 8 MB image takes at least 322 ms to configure, longer than the 100 ms PCIe budget; Tandem configuration is not available with the Basic licence).

## Not covered
No link has been available on the bench: enumeration, MSI delivery, XDMA transfers to a real host and the class-code change are unverified. A BAR0 larger than 64 KiB, a user port clock other than `ui_clk`, and a user interrupt through MSI-X are not built.
