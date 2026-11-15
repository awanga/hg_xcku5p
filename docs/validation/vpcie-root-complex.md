# Logical PCIe root complex (variant 2, stage 1)

Decision 0008. Status 2026-11-15: RTL, unit tests, device tree and kernel configuration written; Vivado build and board test in progress (see the end of this file for results).

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
