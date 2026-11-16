# Logical PCIe root complex (variant 2, stages 1 and 2)

Decision 0008. Status 2026-11-15: RTL, unit tests, device tree and kernel configuration written; Vivado build (WNS +0.003, WHS +0.006, 27.3k LUT, 33.8k FF, 45.5 BRAM, 4 URAM; `build/soc/vv_vpc1`, ExtraTimingOpt, first try) and board test done.

## What it is
The CPU's own Linux sees a generic ECAM PCI host bridge (`pci-host-ecam-generic`) with one device, 00:00.0 (10ee:9034), implemented in fabric (`fpga/rtl/vpcie.v`, wrapped with `pcie_regs` by `fpga/rtl/vpcie_ep.v`). BAR0 (64 KiB) forwards to the same host window of `pcie_regs` that the XDMA host uses on the real endpoint; the CPU side of `pcie_regs` stays at 0xF800A000. So one Linux plays both roles: host-side drivers/tools through the PCI core, firmware-under-test through 0xF800A000.

| Item | Value |
|---|---|
| Netlist | `fpga/scripts/cpu/gen_vpcie_soc.sh` -> `soc_l2u_128k_w4v` (default netlist plus a 2 MiB peripheral region at 0xF9000000) |
| Build | `build_soc.tcl ... soc_l2u_128k_w4v ... -vpcie` (crossbar slave 13, 21-bit window) |
| ECAM | 0xF9000000, 1 MiB, bus 0 only |
| BAR window | 0xF9100000, 1 MiB (PCI address = CPU address) |
| INTx | INTA from `pcie_regs` CPU doorbell (cpu_db_any), PLIC source 10, masked by command bit 10 |
| Kernel | `KVPCIE=1` (PCI, PCI_HOST_GENERIC, UIO, UIO_PCI_GENERIC); DTS `hg-xcku5p-sdroot-vpcie`; pciutils in the rootfs |
| BAR1 (stage 2) | 64 KiB, the XDMA-compatible DMA registers (`fpga/rtl/vdma.v`); BAR0 keeps the firmware-facing register block |
| DMA memory | host buffers and card memory are DDR4 regions behind the hub DMA port (reserved-memory 0x7E100000 and 0x7E000000, 1 MiB each); the firmware opens the card window (WIN_BASE/WIN_SIZE at 0xF800A070/74, closed at reset) and the engine refuses a descriptor whose card side is outside it |
| Not implemented | MSI/MSI-X, capability list, extended config space, bus-mastering effects (the engine ignores the command register's bus-master bit), streaming/bypass, poll-mode write-back, byte-granular addresses and lengths (multiples of 8 only) |

## Evidence
- `tests/rtl/tb_vpcie.v` (Icarus, Verilator; read/write ready delays 0 and 3): 60 checks of the header layout, sizing, BAR assignment and moves, memory-enable gating, absent functions, INTx and its mask, reset; 12 mutants all caught.
- DTS: `tests/dts/run.sh` passes with the new tree; `tests/dts/xbar_map.csv` has slave 13.
- Board (JTAG load of `vv_vpc1/soc.bit`, SD image built with `KVPCIE=1 KHDMI=1 DTS_NAME=hg-xcku5p-sdroot-vpcie`): `tools/smoke.py --vpcie --net` passes all 16 base checks, the 5 `--vpcie` checks and the Ethernet link check. The ping to the gateway 192.168.1.1 lost 1 of 3 in 2 of 4 runs; the cause is the gateway, not the build: the dev PC itself loses 8% of 50 pings to it, while the board pings the dev PC (192.168.1.167) 100/100 at 0.47 ms. Use the dev PC as the `--net` target. Observed: `lspci` shows 00:00.0 "Memory controller: Xilinx 9034" with BAR0 at f9100000 (32-bit, non-prefetchable, 64K) and INTA routed to PLIC 10; with memory decoding enabled BAR0+0 reads 0x50434901 and the mailbox written through BAR0 is read at 0xF800A020 (and the reverse); `uio_pci_generic` binds, a CPU doorbell raises exactly one interrupt (/proc/interrupts, PLIC source 10) and the status INTx bit; a read through BAR0 with memory decoding off returns 0xFFFFFFFF (master abort) as in the unit test.
- First smoke run failed three of the new checks, all test mistakes (memory decoding is off until a driver or setpci enables it, as on real PCI; busybox devmem takes no `addr+offset`; the INTx check did not parse). Fixed in `tools/smoke.py`.
- Usage: `setpci -s 00:00.0 COMMAND=0002`, then `devmem <BAR0+offset>` is the host view, `devmem 0xF800A000+offset` the firmware view; `uio_pci_generic` exposes /dev/uio0 for userspace INTx tests.
- Limits: no DMA, no MSI, no capabilities; the CPU cannot see PCIe-level behaviour (see decision 0008).

## Stage 2: XDMA-compatible DMA subset
`fpga/rtl/vdma.v` follows the AMD PG195 register layout as far as the vendor example bench exercises it (channel control 0x04, status 0x40/0x44, completed count 0x48, descriptor address 0x4080/0x5080, 32-byte descriptors with magic 0xAD4B, taken from the generated `sample_tests.vh` and `usp_pci_exp_usrapp_tx.v`); the identifier, interrupt-enable and request registers and the status bit positions are written from memory of PG195, which is not available in this tree (`docs/external` holds no copy), so they are **not verified against the vendor document or driver**. The register list is in the header of `vdma.v`. The legacy interrupt now follows the XDMA rules: the CPU doorbell is user interrupt 0 and needs the IRQ block's user enable (0x2008); channel events need the control-register enable and the IRQ block's channel enable (0x2014).
- Unit test `tests/rtl/tb_vdma.v` (107 checks, memory latency 0 and 2, Icarus and Verilator) with a byte-array AXI memory and the pattern as independent model: identifiers, H2C and C2H, three-descriptor chains with 4 KiB crossings on either side, window edges (exact start, exact end, one word past, below, closed), every error status (magic, length, alignment, address above 4 GiB, descriptor/read/write AXI errors), restart, interrupts, simultaneous channels, run cleared mid-chain, no burst across 4 KiB and none above 16 beats. 24 mutants caught. The bench found one engine bug: an AR was raised for a descriptor address above 4 GiB.
- Integration test `tests/rtl/tb_vpcie_dma.v` (`vpcie_ep`: enumeration, BAR0 and BAR1 programming, H2C and C2H through BAR1, the window opened by the CPU side, interrupt gating and clearing); 5 routing mutants caught.
