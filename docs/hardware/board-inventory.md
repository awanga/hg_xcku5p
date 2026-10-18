# Board inventory

Source: `docs/external/hg_xcku5p_sch.pdf` (13 sheets, dated 11/10/2025; revision field blank). Board revision of the
physical unit is not recorded: confirm it matches.
Evidence levels: **S-text** = from the PDF text/netlist layer (reliable), **S-image** = read from a rendered sheet at
low resolution (verify by zooming), **owner** = stated by the board owner, **datasheet-memory** = from memory, unchecked.
The owner is compiling a full pin list; `schematic-pin-extract.csv` is only a cross-check (netlist-derived, 330+ pins).
Net names in the PDF netlist have `_` replaced by `0`; the CSV is decoded against the printed labels.

## Clocks
| Clock | Pins | Notes | Evidence |
|---|---|---|---|
| USER_CLK1 100 MHz (X1 oscillator, AC-coupled) | T24 (P) / U24 (N) | Bank 65 (VCCO 1.2 V), GC pins; usable as DDR4 system clock or fabric clock. Matches owner. | S-text, S-image |
| GTCLK 156.25 MHz | T7 (P) / T6 (N) | MGTREFCLK1 of bank 225. Matches owner. | S-text |
| CLK_50M | E18 | 50 MHz oscillator via 43R, bank 67 (VCCO = VADJ). | S-text, S-image |
| PCIe refclk | AB7 (P) / AB6 (N) | MGTREFCLK0 bank 224. | S-text |
| FMC GTY clocks | K7/K6, M7/M6 | | S-text |

## Configuration flash — MT25QU256ABA1EW9-0SIT (U15)
- Schematic part matches the owner-stated part number. 256 Mb, 1.8 V (VCC = +1.8 V). **S-text**
- Wired to dedicated config pins (bank 0, VCCO +1.8 V): CS#=AA12, CLK=Y11, DQ0..3 = AD11, AC12, AC11, AE11 => x4 QSPI. **S-image**
- Mode pins: M2 (AF12)=GND, M1 (AA9)=GND, M0 (AA10)=+1.8 V => M[2:0]=001, Master SPI. **S-image; verify against UG570**
- DONE=AB11 (LED10), PROGRAM_B=AB9 (RST_1V8 net, button SW2 via TPS3801 supervisor), INIT_B=W10 (2K to 1.8 V).
- Vivado properties to set once confirmed: `CONFIG_MODE=SPIx4`, `CONFIG_VOLTAGE=1.8`, `CFGBVS=GND`/VCCO as appropriate,
  `BITSTREAM.CONFIG.SPI_BUSWIDTH=4`; flash part name `mt25qu256-spi-x1_x2_x4`.

## DDR4 — 2 x MT40A256M16GE-075E (U22, U23), 32-bit
- Schematic confirms two MT40A256M16GE-075E; DQ0..31, DQS0..3 (P/N), DM0..3 (DM_DBI used as DM), single CS#, CKE, ODT,
  BG0 only (x16 parts have one bank group pin), BA0-1, A0-A13, ACT_n, ALERT_n, PAR, RESET_n. **S-text**
  => 2 x 4 Gb x16 = 1 GiB, one rank, no ECC.
- Banks 64 (data) and 65 (address/command/clock) at VCCO +1.2 V. **S-image** Command-bus topology (fly-by vs T) not yet reviewed.
- -075E is the DDR4-2666 bin; the achievable rate on a -2 speed-grade KU5P in this topology must be taken from DS922/PG150
  and calibration, not assumed. **datasheet-memory**
- Bank 65 also carries HDMI TMDS, KEY_PL0-3, SW1-4, PCIE reset-related and PMOD pins at 1.2 V (see matrix).

## UART / USB (sheet 13)
- USB-C (J6) -> USB2513 hub (U11) with 93LC56B EEPROM (U9, wired to the FT232H, not the hub; **S-image**).
  Correction to the working notes: the 93LC56B EEPROM is attached to the **FT232H** (EECS/EECLK/EEDATA), not the USB2513.
- Hub port 1: **FTDI FT232HQ (U31)**, MPSSE: ADBUS0-3 = TCK/TDI/TDO/TMS via 43R series resistors to the FPGA JTAG pins
  (TCK AE12, TDI AB12, TDO Y10, TMS AB10). **S-text, S-image**
- Hub port 2: **CP2105 (U10)**, VIO = +1.8 V. UART1 = SCI (enhanced), UART2 = ECI (standard). **S-image**
  | Signal | FPGA pin |
  |---|---|
  | UART1_PC2FPGA (CP2105 TXD_SCI) | H16 |
  | UART1_FPGA2PC | G16 |
  | UART2_PC2FPGA | H17 |
  | UART2_FPGA2PC | G19 |
  All four confirmed against the schematic. They sit in bank 67 (VCCO = **VADJ**). The CP2105 side is 1.8 V, so VADJ **must be
  the 1.8 V jumper position** (CON3 selects 1.8/2.5 V); at 2.5 V the FPGA would drive above CP2105 VIO. **S-image**
- RISK: JTAG nets go from the FT232H (3.3 V I/O, VCCIO +3P3V) to bank 0 (VCCO 1.8 V) through 43R with no visible level
  translator. Check I/O voltage of the FT232H VCCIO pins (the figure suggests +3P3V) before relying on it. **S-image, unresolved**
- Vivado `hw_server` does not drive a generic FT232H natively; plan on openFPGALoader or an XVC bridge. **datasheet-memory**

## Ethernet — RTL8211EG (U30), RJ45 with integrated magnetics (J4)
- FPGA side is an 8-bit data path: TXD0-7, RXD0-7, GTX_CLK, TXCLK, RXCLK, TX_EN/ER, RX_DV/ER, RSTB (all bank 87, 3.3 V). **S-text**
- Note on the sheet: "GND: GMII (default)", "3V3: RGMII" at the COL strap; the strap resistors as drawn are ambiguous
  (R153 to 3.3 V, R159 to GND, R158 NC; RXD6/RXD7 pulled to 3.3 V via R156/R157). Mode **unresolved**: needs a zoomed look
  and the RTL8211EG datasheet. GMII 1000 Mb/s through 3.3 V HDIO pins is a timing risk at 125 MHz; RGMII would be easier.
- **MDC/MDIO have no FPGA pin** (PHY pulls them to 3.3 V; nets ETHPL_MDC/MDIO exist only on the PHY sheet), likewise INT,
  COL, CRS. The PHY runs on strap defaults only; Linux cannot read PHY registers. **S-text**
- PHY crystal 25 MHz; LED0/LED1 to RJ45 LEDs. CLK125 unconnected.

## SD card (J8, micro-SD)
- CLK AE15, CMD AD15, DAT0..3 = AF13, AE13, AF15, AF14 (bank 84, 3.3 V), 4.7K pull-ups. **S-text**
- No card-detect or write-protect wired to the FPGA; no level shifter or power switch visible => 3.3 V signalling only
  (default / high-speed modes, no UHS-I). **S-image**

## I2C, sensors, misc (sheet 4)
- PL_I2C: SCL AB14, SDA W16, 2.2K pull-ups, BL24C02 (U4). **S-text/S-image**
- Second bus "SCL/SDA" (A9/B9, bank 86, 4.7K pull-ups): two BL24C256 (U25, U16). Address straps not read. **S-image, verify**
- FMC_SCL/FMC_SDA (K9/K10): FMC connector EEPROM bus. **S-image, verify**
- MS5611-01BA03 (U8), **owner-confirmed pinout 2026-10-18**: wired as **SPI** (PS=GND), 3.3 V (bank 86), 100R series.
  CSB B10 (active low), SCLK B11, SDI (MOSI) C11, SDO (MISO) A10. Not I2C; no interrupt line. Upstream Linux driver:
  IIO `ms5611` SPI (`meas,ms5611`, SPI mode 0/3, <= 20 MHz per datasheet-memory); needs an AXI SPI controller + chip select. **S-text/S-image**
- Temperature sensor is a **DS18B20** (1-Wire, W13, 4.7K pull-up; also header J11). Owner's "DS18820" is a typo. **S-text**
- Buzzer: BEEP W12 (NMOS Q1 drive, active high). Fan: PWM E15, FB G17.
- LEDs LED0-7 (**owner-confirmed**): E16, E17, F15, D15, B16, D18, G15, E22. Each drives the gate of an SI2300 NMOS
  (1K series, 20K pulldown) switching a red LED from +3.3 V => **active high** (drive 1 = on), default off. Bank 67 (VADJ:
  gate drive is 1.8 or 2.5 V; fine for the SI2300). LED9 = +5 V power, LD10 (blue) = DONE (not software-controllable).
- Keys KEY_PL0-3 (**owner-confirmed**): T19, N22, N21, P19, bank 65 (VCCO 1.2 V => LVCMOS12). Pushbuttons K1-K4 connect the
  input to +1.2 V through 1K, with 20K to GND => **active high when pressed**, idle low. No hardware debounce.
  Switches SW1-4 (4-position DIP): N19, N23, R21, R20, bank 65, 1.2 V, 10K series, DIP sense polarity to be read at zoom.
- PMOD0 (J1), PMOD1 (J2), PMOD2 (J3) at 3.3 V; PMOD3 (J12) via TXS0108E level translator (bank 66).
- FMC_PWRGD W15; PCIE reset F22.

## HDMI (sheet 5) — output only
- TMDS pairs on bank 65 (VCCO 1.2 V): CLK U25/T25, D0 P24/N24, D1 W24/V24, D2 W23/V23 (N/P as listed in the CSV).
- Connector side: 100 nF AC coupling, 51R pull-ups to +3.3 V on the connector side; 5 V via TPS2051 switch (HDMI1_OUT_EN Y16), HPD AB16
  via buffer. **S-image**
- DDC/CEC: connector SDA/SCL go through PCA9306 (U27) to nets **FPGA_I2C_SCL1/SDA1, which have no FPGA pin** in the
  netlist. EDID read from the FPGA therefore appears impossible. Needs confirmation by the owner against the board. **S-text**
- RISK: TMDS from a 1.2 V HP bank, AC-coupled, is not a standard-compliant HDMI source. Treat as experimental. Deferred workstream.

## PCIe / QSFP / FMC
- QSFP: 4 lanes on bank 225 (V/Y/T/P RX), refclk T7/T6. FMC HPC (bank 66/67
  LA pairs + GTY bank 227 DP0-7), VADJ rail. See CSV. All deferred per README.

## PCIe Gen3 x4 edge connector (sheet 8) — **owner-confirmed pinout**
- Physical x4 edge (PCIEX4). All four lanes land on GTY quad 224. FPGA pin map (from netlist):
  | Lane | RX P/N (from host) | TX P/N (to host) |
  |---|---|---|
  | 0 | AB2 / AB1 | AC5 / AC4 |
  | 1 | AD2 / AD1 | AD7 / AD6 |
  | 2 | AE4 / AE3 | AE9 / AE8 |
  | 3 | AF2 / AF1 | AF7 / AF6 |
  REFCLK (slot 100 MHz): AB7 (P) / AB6 (N) = MGTREFCLK0 of quad 224, via 100 nF AC coupling. TX pairs are AC-coupled on the board
  (100 nF); RX pairs are direct. **S-text/S-image**
- PERST# (slot A11) -> 1K -> F22 (`PCIE_RESET`), with a 10K pull-up to **+3.3 V** on the slot side. F22 is in bank 66
  (VCCO = VADJ 1.8/2.5 V), so the 3.3 V net drives a 1.8/2.5 V pin through 1K; the clamp current is small but out of spec
  for continuous operation. Confirm acceptable and use an input with the internal clamp in mind; or treat as a risk. **S-image**
- PRSNT#1 (A1) is tied to PRSNT#2 at B17 and B31 (0R), advertising the card as present for x1/x4. No SMBus, WAKE#, JTAG, 3.3 V/3.3VAUX
  connections (pins crossed out). +12 V from the slot goes to +12V_PCIE through a diode.
- Gen3 x4 capability: XCKU5P-2 has a PCIE4 hard block and GTY lanes rated for 8 GT/s; Gen3 x4 is feasible in principle, but the
  block location, lane ordering/polarity against this quad must be checked in Vivado (needs the device installed). Not validated. **datasheet-memory**
- Role: PCIe endpoint (the board is the card). Deferred workstream, not MVP.

## Power rails (sheet 9)
- Two ADP5054 regulators: +0.85 V, +0.9 V, +1.2 V, +1.8 V, +2.5 V, +3.3 V, +5.0 V, +ADJ (1.8/2.5 V jumper), from +12 V. **S-image**
