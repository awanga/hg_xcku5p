# Board inventory

Confidence: **owner-stated** = given by the board owner in chat, not checked against the schematic.
Schematic is not yet in the repository; pins, polarity, banks and voltages are all UNKNOWN until it is.

## Configuration flash — MT25QU256ABA1EW9-0SIT (owner-stated)
- Micron MT25QU256: 256 Mb (32 MiB) QSPI NOR, 1.8 V I/O. Part-number decoding is from memory of the Micron
  naming scheme; verify against the datasheet before relying on it.
- Unknown: wiring (QSPI x1/x2/x4, CCLK via STARTUPE3), config bank voltage (must be 1.8 V), mode straps, write-protect/reset pins.
- Vivado config properties to derive once confirmed: `CONFIG_MODE`, `SPI_BUSWIDTH`, `CONFIGRATE`, `CONFIG_VOLTAGE`; flash part name for `cfgmem`.

## DDR4 — 2 x MT40A256M16GE-075E (owner-stated), 32-bit bus
- Each device: 4 Gb, x16, 512 MiB; -075E = DDR4-2666 speed bin (Micron naming; verify). Two devices side by side
  => 32-bit data bus, 1 GiB total, one rank, no ECC.
- Achievable rate is bounded by XCKU5P -2 speed grade and the UltraScale+ DDR4 controller limits for the actual
  topology/bank; do not assume 2666 Mb/s. Check PG150 and the schematic.
- Unknown: pin map/byte lanes, bank voltage (1.2 V), system clock source and frequency, reset, ODT/CKE/CS wiring,
  ALERT_n/PAR, trace length (affects calibration/rate), whether the part uses a 1.2 V VPP rail.
- A 32-bit bus with x16 devices means the controller must be configured for 32-bit, 2 components, no ECC.

## Everything else
Not yet inventoried (Ethernet PHY, SD, I2C, GPIO, HDMI, FMC, UART/JTAG bridge, clocks): see TASKS.md Phase 1.
