# 0008: PCIe build variants and how the endpoint is tested without a host

- Status: proposed 2026-11-15 (owner request: explore an internal root complex and a CPU-less PCIe-only build; the default stays CPU + PCIe endpoint). Nothing here changes the default build.
- Context: the board is a PCIe endpoint (edge connector, Gen3 x4, GTY quad 224, PCIE4 block X0Y0). No slot or PC is available on the bench, so the link, enumeration and host access cannot be exercised on the board today (README, owner note 2026-11-15).

## Facts established
- The XCKU5P has exactly one PCIe hard block (`PCIE40E4_X0Y0`; Vivado `get_sites`, 2026-11-15, no PCIE4C). It is the endpoint's block, so an on-chip hard-IP root port wired to the endpoint cannot exist. Even a second block would need its lanes cabled to the first block's pins, which go to the edge fingers (AC-coupled TX) or the QSFP/FMC connectors.
- The external PIPE interface of the PCIe4 IP exists for simulation only (the vendor root-port test bench uses it); on silicon the block talks to the GTY transceivers.
- A soft root complex with its own PHY on GTY would have to implement PCIe link training, equalisation and a TL/DL layer: out of scope.
- What a simulation already proves (tests/pcie, xsim, vendor root-port model, Gen3 x4): link training, enumeration, BAR access through the endpoint wrapper, mailbox and doorbells, user interrupts, DMA through the window filter. What it cannot prove: behaviour on the board's GTY lanes, the slot's reference clock, PERST# levels, or a real host's enumeration and driver.

## Variant 1 (default): CPU + PCIe endpoint
As implemented: `build_soc.tcl -pcie`. The CPU runs the firmware that serves the host (pcie_regs mailbox/doorbell, DMA window into DDR). Verified in simulation; on the board only that it builds, boots and reports "link down, no clock" (no slot).

## Variant 2: CPU + logical PCIe host (host emulator), proposal
Goal: run the endpoint firmware on the CPU against something that behaves like the host, before a PC is available.
- Replace the XDMA core by a fabric **host emulator** that drives exactly the two interfaces the core drives: the host-side AXI4-Lite window of `pcie_regs` (what BAR0 reads/writes become) and AXI4 bursts into `axi_win`/the hub DMA port (what H2C/C2H become), and that receives the CPU-to-host user interrupt request (`usr_irq_req`/`usr_irq_ack`).
- Control through a test rig on UART2 (`/dev/ttyUSB1`, pins H17/G19, free) with a line protocol (`W addr data`, `R addr`, `B addr len` for bursts, `I` for interrupt status); a Python script then plays the host: write a mailbox, ring a doorbell, start a "DMA", check the CPU's answer. UART1 stays the Linux console.
- Tests the firmware, `pcie_regs`, `axi_win`, the DMA port arbitration, interrupts to the PLIC and timing of the SoC side on the real board. Does not test the PHY, config space, XDMA descriptors or MSI delivery (those stay with the IP simulation and the PC test).
- Cost: small RTL (UART line parser, AXI-Lite and AXI4 master), no GTY/PCIe IP in this build (saves about 15k LUT and the XDMA timing risk), built as `-pcie-emu`.

## Variant 3: PCIe only, no CPU, proposal
Goal: an FPGA card with no soft CPU where the host PC drives the bus through BAR0 (AXI-Lite) and the XDMA AXI master.
- Build without `SOC_MODULE`: XDMA master (128-bit, 250 MHz) -> clock converter -> a crossbar to the DDR4 controller's AXI port and the peripheral crossbar (UART, GPIO, I2C, SPI, HDMI registers, LiteEth) in the existing 100 MHz domain. The CPU, OpenSBI and Linux are absent; the host loads and controls everything.
- Open points: the DDR4 controller user interface is 256-bit at 333 MHz (the XDMA side needs a data-width and clock converter, about 2.6 GB/s ceiling); the peripheral crossbar masters currently are the CPU and `eth_dma`; interrupts need an MSI mapping instead of the PLIC; reset ownership moves to the host (PERST# only).
- The same UART2 rig as in variant 2 can inject the BAR accesses when no PC is attached; the injector is shared code.
- Cost: moderate; mostly new top-level wiring and constraints, the peripheral IP and the XDMA wrapper are reused.

## Recommendation
Build variant 2 first (it answers "can I test the firmware without a PC"), sharing the UART line injector with variant 3, and keep variant 3 as a scoped follow-up after the default endpoint has met timing and booted. The default build remains CPU + PCIe endpoint.
