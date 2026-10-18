# 0004 — DDR4 controller configuration

- Status: accepted for bring-up (baseline); not validated on hardware
- Date: 2026-10-18

## Context
Two MT40A256M16GE-075E on a 32-bit bus (docs/hardware/board-inventory.md), banks 64/65 at 1.2 V, 100 MHz USER_CLK1
(T24/U24) available as the controller reference. Address/command are fly-by to both devices with 39R pull-ups to VTT,
single CS/CKE/ODT/CK pair, PAR and ALERT_n wired to the FPGA.

## Decision
AMD DDR4 SDRAM (UltraScale+) IP, `Complete_Memory_Controller`, AXI4 interface (256-bit, 30-bit address = 1 GiB),
DM_NO_DBI, no ECC, no CA parity, 100 MHz differential system clock. Baseline **tCK = 1250 ps (DDR4-1600, ui_clk 200 MHz)**.
The IP accepts a 100 MHz input at tCK 750 (2666), 1000 (2000), 1250 (1600) and 1500 ps; it rejected 833, 937, 1071, 1125 ps.
Speed is raised only after calibration passes at the baseline and the margin is measured; the -2 grade and the board
topology may limit it below the -075E part's 2666 rating (unverified, see PG150/DS923).
Pins: `fpga/constraints/ddr4_pins.xdc`, generated from the schematic extract; RAS_n/CAS_n/WE_n map to adr[16]/[15]/[14].

## Consequences / open points
- PAR is terminated to VTT (0.6 V), neither a logic level. With CA parity off the IP has no parity port, so U20 is not
  driven: the DRAM sees an undefined PAR input. JEDEC requires a valid level or parity enabled; resolve by enabling
  parity (IP option) and checking the port list, or accept the risk until calibration shows a problem. **Open.**
- ALERT_n (R23) is pulled to 1.2 V and unused by the IP without parity.
- Vivado reports DRC DCIRST-1 for 26 SSTL12_DCI ports ("no DCIRESET primitive"). The IP adds DCIRESET only when its
  own bank selection says banks 60/65/70 use DCI; the IP here has no pin-selection input (pins arrive via XDC), so its
  generated PHY has `DCIRST_IOSTD_BANKS = "false"`. Unresolved whether this matters; AR#000038677. **Open.**
- The IP was never told the pin map other than through the XDC; its own pin-rule validator (GUI) has not been run.
- UART/LEDs in bank 67 need VADJ = 1.8 V; KEY_PL0 resets the controller.

## Validation
Pending: board calibration, memtest passes, bandwidth (the design reports wr/rd cycles per pass over UART).

## Revisit triggers
Calibration failure; parity/PAR resolution; raising tCK target.
