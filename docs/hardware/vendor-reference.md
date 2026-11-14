# Vendor reference package (analysis)

The board vendor's tutorials and example projects are kept locally in `docs/external/vendor_docs/` (gitignored, not redistributable; 773 MB).
This note records what they contain and how they compare with our schematic-derived data (`board-inventory.md`, `schematic-pin-extract.csv`).
Facts below come from the vendor's XDC files, IP configuration and tutorial text (Chinese); the examples are Vivado projects for the same
XCKU5P-FFVB676 and use a 50 MHz `CLK_50M` (E18). Evidence level: vendor material, not board-tested by us unless stated.

## Contents
| # | Topic | Useful for |
|---|---|---|
| 1, 2 | LED, flash programming (Quad-SPI) | LED pins; bitstream config properties |
| 3, 4 | QSFP IBERT 40G (4 x 10.3125 Gb/s), 100G (4 x 25.78125 Gb/s) | GTY quad 225 refclk and line rates |
| 5 | XDMA PCIe x4 | PCIe pins, reset, refclk |
| 6 | DDR4 IP + AXI command read/write | independent DDR4 pin and IP settings |
| 7 | HDMI (1024x768@60, 65 MHz pixel, 650 MHz serial) | TMDS pins |
| 8 | SD card over SPI | SD pins (confirms SPI mode) |
| 9 | AD9361 | none: the sub-board tutorial is sold separately |
| 10, 11, 12 | buzzer PWM, fan PWM/tach, DS18B20 1-Wire | pins and drivers for small peripherals |
| 13, 14 | UART to AXI-Lite master; MS5607 barometer over SPI | sensor bring-up sequence |

There is no Ethernet, FMC or user-flash example: the GMII constraints and PHY behaviour still rest on the schematic and the RTL8211EG datasheet.

## Cross-check against the schematic extract
- DDR4: the vendor `ku5p_ddr4.xdc` has 69 port-to-pin entries; the 67 shared with `fpga/constraints/ddr4_pins.xdc` are identical (the other two are the
  vendor's calibration LED E22 and reset P19). We additionally constrain `par`, `ck_c` and `dqs_c`; the vendor leaves PAR unconstrained, which matches
  the open "PAR undriven" item (no CA parity in either design).
- DDR4 IP settings in the vendor project: 32-bit, tCK 750 ps (DDR4-2667), 100 MHz differential input clock, CL 19, CWL 14, 4:1, 1.2 V, DM_NO_DBI,
  no ECC, row-column-bank map: the same as ours. **Discrepancy:** its `MemoryPart` is `MT40A512M16LY-075` (8 Gb parts, 2 GiB) while its tutorial text says
  `MT40A256M16GE-075E` (4 Gb, 1 GiB), which is what we use. The board test of 2026-11-08 shows 4 Gb parts (1 GiB), so the vendor IP over-declares the density (docs/validation/ddr4-bringup.md).
- LEDs: the 8-LED example maps D18, E17, B16, D15, E16, F15, G15, E22 to the schematic nets LED5, LED1, LED4, LED3, LED0, LED2, LED6, LED7; they match
  the extract (the vendor's port order is arbitrary). LEDs are active high (tutorial 1).
- SD: AF14 (DAT3/CS), AE15 (CLK), AD15 (CMD/MOSI), AF13 (DAT0/MISO), LVCMOS18, SPI mode: same pins as `soc_board.xdc`. IOSTANDARD differs: the vendor uses LVCMOS18, we use LVCMOS33 (bank 84 at 3.3 V per the inventory; our setting is the one that boots Linux from the card).
- PCIe: lanes TX0-3 AC5/AD7/AE9/AF7, RX0-3 AB2/AD2/AE4/AF2, refclk AB7, PERST F22 (pin function `PERSTN0_65`, matches the extract).
- HDMI: TMDS clock T25, data N24 / V24 / V23 (LVDS), output enable Y16 (LVCMOS33; schematic net `HDMI1_OUT_EN`, the vendor calls it HDMI0_OE). 65 MHz pixel clock from a
  50 MHz MMCM with a 650 MHz serial clock (10:1 DDR).
- QSFP: quad 225, refclk 156.25 MHz on MGTREFCLK1 (T7/T6); an unused MGTREFCLK0 pair V7/V6 is constrained too. Both IBERT examples use the same
  pins; only line rate differs.
- Buzzer W12 LVCMOS33 (active high through an NMOS); fan PWM E15 / tach G17; DS18B20 W13 with a 4.7 k pull-up; MS5607/MS5611 on SPI (PS tied to GND),
  3.3 V, bank 86. The vendor XDC files for these four projects are empty in the archive, so only the tutorial text is available: it confirms the signal names (FAN_PWM, FAN_FB), the DS18B20 pull-up, the SPI mode and bank 86; the pin numbers above are from the schematic extract.
- Reset and keys: the SD and HDMI examples use R20 (schematic `SW4`) with LVCMOS18 for reset; the buzzer example uses T19 (`KEY_PL0`) with LVCMOS12. Our inventory
  puts the keys in bank 65 (1.2 V), so the vendor's LVCMOS18 on R20 should not be copied before checking that pin's bank voltage.

## Settings worth reusing (not yet in our builds)
- Flash boot (tutorial 2): `CONFIG_MODE SPIx4`, `BITSTREAM.CONFIG.SPI_BUSWIDTH 4`, `BITSTREAM.CONFIG.CONFIGRATE 51.0`, `BITSTREAM.GENERAL.COMPRESS TRUE`,
  `BITSTREAM.CONFIG.UNUSEDPIN Pullup`. Our `build_soc.tcl` sets none of them (we configure over JTAG). The flash is 256 Mb: confirm 4-byte addressing and
  `CFGBVS`/`CONFIG_VOLTAGE` when the flash-boot task is done.
- MS5607-02BA and MS5611 share the driver sequence: reset 0x1E, wait 2.8 ms, read PROM 0xA0-0xAE (8 words, CRC-4), convert, read ADC. SPI mode 0 or 3, up to 20 MHz.
  The vendor tutorial says MS5607; the owner and schematic say MS5611-01BA03; Linux IIO `ms5611` handles both compatibles, and the board test confirmed an MS5607 (docs/validation/small-peripherals.md).
- Vendor drivers are written for a 50 MHz clock and a polling FPGA state machine (UART-to-AXI-Lite bridge, 1-Wire, PWM); in our SoC these become Linux drivers
  (`w1-gpio` or a bit-banged AXI GPIO for DS18B20, `pwm-fan`/`pwm-beeper`, IIO `ms5611`). They need AXI GPIO/PWM/SPI IP or small RTL blocks; none exists yet.

## Not covered (still need the schematic/datasheets)
Ethernet PHY timing and GMII constraints, FMC pin mapping and VADJ, USB, PMOD level translator, AD9361 sub-board, user QSPI flash content, HDMI DDC (not wired).
