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
- MAC candidates: LiteEth (BSD-2-Clause, has GMII and RGMII PHYs, upstream Linux `liteeth` driver) vs AMD AXI Ethernet
  Subsystem (licensed IP). Decide with the CPU/SoC choice.

## Validation
Pending: simulation of the MAC/PHY wrapper, timing closure, board loopback/iperf. Nothing here is board-tested.

## Revisit triggers
GMII timing cannot close on HDIO; RGMII rework accepted; MDIO access is added by rework.
