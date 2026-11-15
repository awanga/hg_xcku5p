# PCIe endpoint (Gen3 x4, edge connector), 2026-11-15

Scope: the board as a PCIe peripheral. No slot or host is available on the bench, so the link, enumeration and host access are verified in simulation only; the board test proves the build, the SoC integration and the CPU-side registers.

## Design
`fpga/rtl/pcie_ep.v`: XDMA core (DMA/Bridge Subsystem for PCI Express, Gen3 x4, PCIE4 block X0Y0, GTY quad 224, 128-bit AXI at 250 MHz, one H2C and one C2H channel, BAR0 = 64 KiB AXI-Lite window, BAR1 = DMA registers, vendor ID 0x10EE device 0x9034) -> 128-to-64 bit downsizer -> clock converter into the CPU clock -> `axi_win` (DMA window filter) -> one slave of the shared hub DMA port crossbar (eth_dma writes, HDMI reads, PCIe both). Host register window: BAR0 -> AXI-Lite clock converter -> `pcie_regs` (mailbox, doorbells, status, DMA window registers). CPU view of the same registers at 0xF800A000 (PLIC source 9 = host doorbell). Pins: board-inventory.md (owner-confirmed lanes, refclk AB7/AB6, PERST# F22 in bank 66 at 1.8 V, which is out of spec for continuous clamp current through the board's 1K from a 3.3 V pull-up: risk recorded, not changed).
Safety: the DMA window is closed after reset (`WIN_SIZE` 0): a host-programmed DMA cannot reach DDR until the CPU opens a window (`axi_win` answers DECERR).
Build: `build_soc.tcl ... -pcie` (needs a netlist with the DMA port). The LiteEth window in the peripheral crossbar was narrowed from 16 KiB to 8 KiB (its CSRs end below 0xF800A000); `tests/dts/xbar_map.csv` tracks it.

## Evidence
| Level | Result |
|---|---|
| Unit tests | `tests/rtl/run.sh`: pcie_regs (68 checks), axi_win (151 checks, STALL 0/1, Icarus and Verilator, seeds 1-7), cdc_cfg (both clock ratios), all with committed mutants (every mutant caught); ALL PASS |
| Root-port simulation | `tests/pcie/run_sim.sh` (xsim, vendor root-port bench regenerated from the IP, PIPE mode, 8 GT/s x4): link training and enumeration checks, BAR0 reads of ID/status over PCIe, mailbox both ways, host doorbell to CPU interrupt, CPU doorbell to user interrupt (request, ack, release), H2C refused with the window closed (status 0x4040, no write reaches memory), H2C and C2H through an opened window, window closed again: `pcie_ep_regs` and `pcie_ep_dma` PASS. The DMA test fails on an `axi_win` that never refuses (mutant run: 4+ errors). |
| Timing | `vv_pcie3` (Performance_ExtraTimingOpt) WNS -0.006, then `postroute_fix.tcl`: WNS +0.000, WHS +0.010 (`build/soc/vv_pcie3f.bit`; 43.7k LUT, 55.3k FF, 83.5 BRAM, 4 URAM). Earlier runs: -0.557 (unpipelined window check, CDC constraints dropped because XDC does not allow Tcl control flow), -0.442 (after the pipeline), -0.183 (CDC fixed, CPU BTB path). |
| Board (JTAG load, SD boot with the HDMI image) | `tools/smoke.py --pcie`: 16 existing checks plus `--pcie` checks (ID 0x50434901, link down and never up, window closed, mailbox, window registers read back) PASS; HDMI scan-out runs (frames counting, late 0) and Ethernet receive works through the shared crossbar (ping 0% loss, iperf3 receive 52.7 Mb/s, 0 errors) |

## Observations and open items
- With no slot, STATUS reads 0x6: the PCIe user clock runs and PERST# reads deasserted, stable over time. Owner statement (2026-11-15): X2 feeds MGTREFCLK1 of bank 225 (T7/T6, the 156.25 MHz GTCLK) and is not isolated, so it always runs; the edge connector REFCLK is on MGTREFCLK0 of bank 224 (AB7/AB6), which this build uses. X2 therefore does not drive the PCIe pair, and my earlier guess that it explained the running user clock was wrong. The cause of a user clock with no slot is not established (floating AC-coupled pair, or the core clocking without a reference); it is informational only. Roles: the edge connector refclk is for the peripheral (endpoint) builds, X2 (bank 225) for a host (root-port) build; a root port would need the quad 224 GTs clocked from the 225 refclk (refclk sharing between neighbouring quads, to be checked in the IP) and its own PERST# output.
- The link cannot come up on the bench: link/enumeration/DMA on silicon are untested. Needed: a PC with a free x4 slot (or an extender) and the owner's go-ahead.
- The vendor ID 0x10EE is the IP default, not an assigned ID for this project.
- Variants without the hard IP (logical root complex on the CPU, CPU-less) are proposed in decisions/0008.
