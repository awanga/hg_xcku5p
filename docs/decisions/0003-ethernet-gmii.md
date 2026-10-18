# 0003 — Ethernet PHY interface: GMII, RGMII optional

- Status: accepted (direction); not validated on hardware
- Date: 2026-10-18

## Context
RTL8211EG (U30) is wired to the FPGA with the full 8-bit GMII bus on HDIO bank 87 (3.3 V). Default strap is GMII;
populating R158 selects RGMII (owner-confirmed). MDC/MDIO/INT are not routed to the FPGA, so the PHY runs on straps.

## Alternatives
- GMII (chosen): board default, no rework, 1000 Mb/s SDR at 125 MHz with 8-bit data.
- RGMII: needs rework (R158), uses only TXD/RXD[3:0] + TX_CTL/RX_CTL, DDR at 125 MHz.

## Decision
Build the MAC/PHY interface for GMII. Constrain pins so the RGMII subset (TXD0-3, RXD0-3, GTX_CLK, RXCLK, TXEN, RXDV) is
the same physical pins, so an RGMII variant is a gateware/parameter change plus R158 rework, not a re-pinning.

## Consequences
- HDIO banks have no IDELAY/ODELAY; RX/TX timing for GMII and especially RGMII must be closed with clock-region placement,
  input/output constraints and the PHY's own timing (RTL8211EG RGMII delay straps), not FPGA delay taps. Check against UG571 once Vivado runs. Datasheet-memory, unverified.
- RXCLK (D14) is an HDGC pin; GTX_CLK (E13) is driven by the FPGA; TXCLK (C13) is only for 10/100 modes.
- 10/100 operation uses the same GMII lanes (nibble) and TXCLK; software must handle speed switching without MDIO
  (PHY autonegotiates; MAC speed must be learned some other way, e.g. fixed 1000 Mb/s or RXD inter-frame status). Open item.
- MAC candidates (kept open until the CPU/SoC path is chosen; no paid TEMAC licence available):
  - LiteEth: BSD-2-Clause, GMII and RGMII PHYs, 1 Gb/s, upstream Linux `liteeth` driver; natural with a LiteX SoC.
  - AMD `axi_ethernetlite` (free): **MII only, 10/100 Mb/s**, upstream `xilinx_emaclite` driver. With this board the PHY is
    strapped GMII and MDIO is not wired, so the link partner/switch must be forced to 100 Mb/s (otherwise the PHY will negotiate
    1 Gb/s and the MII-only MAC sees nothing). COL/CRS are not wired to the FPGA (tie low; full duplex only).
  - AMD AXI Ethernet / TEMAC: licensed IP; the catalog lists them, but a bitstream needs a paid licence (user: none). Not usable.
  - Third-party GMII MAC cores (e.g. verilog-ethernet, MIT) need their own DMA and a custom Linux driver.
## Validation
Pending: simulation of the MAC/PHY wrapper, timing closure, board loopback/iperf. Nothing here is board-tested.

## Revisit triggers
GMII timing cannot close on HDIO; RGMII rework accepted; MDIO access is added by rework.
