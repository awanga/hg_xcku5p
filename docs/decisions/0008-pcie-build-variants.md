# 0008: PCIe build variants and how the endpoint is tested without a host

- Status: proposed 2026-11-15 (owner request: explore an internal root complex and a CPU-less PCIe-only build; variant 2 revised to a CPU-as-root-complex design; the default stays CPU + PCIe endpoint). Nothing here changes the default build.
- Context: the board is a PCIe endpoint (edge connector, Gen3 x4, GTY quad 224, PCIE4 block X0Y0). No slot or PC is available on the bench, so the link, enumeration and host access cannot be exercised on the board today (README, owner note 2026-11-15).

## Facts established
- The XCKU5P has exactly one PCIe hard block (`PCIE40E4_X0Y0`; Vivado `get_sites`, 2026-11-15, no PCIE4C). It is the endpoint's block, so an on-chip hard-IP root port wired to the endpoint cannot exist. Even a second block would need its lanes cabled to the first block's pins, which go to the edge fingers (AC-coupled TX) or the QSFP/FMC connectors.
- The external PIPE interface of the PCIe4 IP exists for simulation only (the vendor root-port test bench uses it); on silicon the block talks to the GTY transceivers.
- A soft root complex with its own PHY on GTY would have to implement PCIe link training, equalisation and a TL/DL layer: out of scope.
- What a simulation already proves (tests/pcie, xsim, vendor root-port model, Gen3 x4): link training, enumeration, BAR access through the endpoint wrapper, mailbox and doorbells, user interrupts, DMA through the window filter. What it cannot prove: behaviour on the board's GTY lanes, the slot's reference clock, PERST# levels, or a real host's enumeration and driver.

## Variant 1 (default): CPU + PCIe endpoint
As implemented: `build_soc.tcl -pcie`. The CPU runs the firmware that serves the host (pcie_regs mailbox/doorbell, DMA window into DDR). Verified in simulation; on the board only that it builds, boots and reports "link down, no clock" (no slot).

## Variant 2: CPU as a logical root complex (revised after the owner's comment 2026-11-15), proposal
Goal: the CPU sees a real PCI(e) host bridge with the endpoint behind it, so a PCI driver (or `lspci`/`setpci`/sysfs resource files) on the board's own Linux can peek, poke and test the peripheral firmware exactly as a PC would, with no hard IP block and no PC.
- **Host side (what Linux sees):** a generic ECAM host bridge (`pci-host-ecam-generic`, no new kernel driver). The DT gives it a 1 MiB ECAM window, a 32-bit MMIO window for BARs and an `interrupt-map` that routes INTA to a PLIC source; kernel options CONFIG_PCI and CONFIG_PCI_HOST_GENERIC. MSI is not provided in the first stage (legacy INTx; drivers fall back to it).
- **Device side (a fabric block, `vpcie`, replacing the XDMA core):** the part of the hard block firmware never programs, as logic: one function with a type 0 config header (the XDMA IDs 10EE:9034, class, BAR0 = 64 KiB register window, BAR1 = DMA/control registers, command register memory-enable / bus-master-enable, INTx pin), absent functions read all-ones, and a BAR decoder that follows the BAR values Linux writes. BAR0 accesses become the same host-side AXI4-Lite transactions `pcie_regs` already serves, so the **peripheral firmware is connected exactly as it is to the XDMA host**: it uses the CPU-side registers (mailbox, doorbells, DMA window) and the `pcie_regs` interrupts.
- **Firmware shim:** peripheral firmware and host driver run on the same CPU (one Linux: a host-side driver or userspace test on one side, the firmware under test on the other through the CPU-side register window, a UIO/devmem or kernel-thread shim), connected only by the logic above. The DMA side is a second stage: an XDMA-register-compatible subset (one H2C and one C2H channel, descriptor lists, status and control per PG195) in fabric, so the vendor driver's register protocol can be exercised; the "card memory" and "host memory" are two reserved regions of the same DDR (`reserved-memory`) and `axi_win` keeps the card side bounded.
- **Costs and prerequisites:** the CPU netlist needs one more peripheral region (ECAM + MMIO, about 4 MiB at 0xF900_0000 via `--memory-region`) and a regeneration with full re-verification (SoC simulation, a Vivado build, the board smoke test); the peripheral crossbar gets a master for it; the kernel configuration gains PCI. No GTY, no PCIe IP: smaller than variant 1 and without its timing risk.
- **Stages:** (1) config space, BAR0 to `pcie_regs`, INTx: enumeration with `lspci`, register peek/poke, doorbell and mailbox between a host-side test and the firmware under test; (2) DMA model and a test driver; (3) optional MSI via a small MSI target that raises the PLIC source.
- **Does not test:** the PHY, link training, the real config-space hardware, XDMA descriptor hardware, TLP-level behaviour, or a PC's enumeration order and driver. Those stay with the IP simulation and the PC test.

## Variant 3: PCIe only, no CPU, proposal
Goal: an FPGA card with no soft CPU where the host PC drives the bus through BAR0 (AXI-Lite) and the XDMA AXI master.
- Build without `SOC_MODULE`: XDMA master (128-bit, 250 MHz) -> clock converter -> a crossbar to the DDR4 controller's AXI port and the peripheral crossbar (UART, GPIO, I2C, SPI, HDMI registers, LiteEth) in the existing 100 MHz domain. The CPU, OpenSBI and Linux are absent; the host loads and controls everything.
- Open points: the DDR4 controller user interface is 256-bit at 333 MHz (the XDMA side needs a data-width and clock converter, about 2.6 GB/s ceiling); the peripheral crossbar masters currently are the CPU and `eth_dma`; interrupts need an MSI mapping instead of the PLIC; reset ownership moves to the host (PERST# only).
- A test rig on UART2 (`/dev/ttyUSB1`, pins H17/G19, free; a line protocol `W addr data`, `R addr`, `B addr len`, `I`) injects BAR-window and DMA-window accesses when no PC is attached; UART1 stays the console of whatever runs.
- Cost: moderate; mostly new top-level wiring and constraints, the peripheral IP and the XDMA wrapper are reused.

## Recommendation
Build variant 2 (logical root complex) first, stage 1 then 2: it answers "can I test the firmware and drivers without a PC" on the board's own CPU. Keep variant 3 (with the UART rig) as a scoped follow-up after the default endpoint has met timing and booted. The default build remains CPU + PCIe endpoint.
