# Logical PCIe root complex (variant 2, stage 1)

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
| Not in stage 1 | DMA model, MSI, capability list, extended config space, bus mastering effects |

## Evidence
- `tests/rtl/tb_vpcie.v` (Icarus, Verilator; read/write ready delays 0 and 3): 60 checks of the header layout, sizing, BAR assignment and moves, memory-enable gating, absent functions, INTx and its mask, reset; 12 mutants all caught.
- DTS: `tests/dts/run.sh` passes with the new tree; `tests/dts/xbar_map.csv` has slave 13.
- Board (JTAG load of `vv_vpc1/soc.bit`, SD image built with `KVPCIE=1 KHDMI=1 DTS_NAME=hg-xcku5p-sdroot-vpcie`): `tools/smoke.py --vpcie --net` passes all 16 base checks, the 5 `--vpcie` checks and the Ethernet link check. The ping to the gateway 192.168.1.1 lost 1 of 3 in 2 of 4 runs; the cause is the gateway, not the build: the dev PC itself loses 8% of 50 pings to it, while the board pings the dev PC (192.168.1.167) 100/100 at 0.47 ms. Use the dev PC as the `--net` target. Observed: `lspci` shows 00:00.0 "Memory controller: Xilinx 9034" with BAR0 at f9100000 (32-bit, non-prefetchable, 64K) and INTA routed to PLIC 10; with memory decoding enabled BAR0+0 reads 0x50434901 and the mailbox written through BAR0 is read at 0xF800A020 (and the reverse); `uio_pci_generic` binds, a CPU doorbell raises exactly one interrupt (/proc/interrupts, PLIC source 10) and the status INTx bit; a read through BAR0 with memory decoding off returns 0xFFFFFFFF (master abort) as in the unit test.
- First smoke run failed three of the new checks, all test mistakes (memory decoding is off until a driver or setpci enables it, as on real PCI; busybox devmem takes no `addr+offset`; the INTx check did not parse). Fixed in `tools/smoke.py`.
- Usage: `setpci -s 00:00.0 COMMAND=0002`, then `devmem <BAR0+offset>` is the host view, `devmem 0xF800A000+offset` the firmware view; `uio_pci_generic` exposes /dev/uio0 for userspace INTx tests.
- Limits: no DMA, no MSI, no capabilities; the CPU cannot see PCIe-level behaviour (see decision 0008).
