# Small peripherals: barometer, 1-Wire temperature, buzzer, fan (2026-11-06)

Bitstream `build/soc/vv_per1` (WNS +0.003 ns, WHS +0.010 ns, Ethernet RX domain +0.445 ns, no DRC violations), kernel 6.18.59 with the drivers below.
All use upstream drivers; the device-tree nodes are in `linux/dts/hg-xcku5p.dtsi`.

| Function | Hardware | Address / PLIC | Linux driver | Result on the board |
|---|---|---|---|---|
| Barometer | second `spi_sifive` master, pins B11 SCLK, C11 MOSI, A10 MISO, B10 CS (bank 86, 3.3 V) | 0xF8005000, source 4 | `spi-sifive` + IIO `ms5611`/`ms5607` | `meas,ms5607` reads 99.87 kPa, 33.6 C; with `meas,ms5611` it read 49.9 kPa (half) |
| Temperature | AXI GPIO bit 0 through an IOBUF on W13 (open drain, board pull-up) | 0xF8003000, source 5 | `w1-gpio` + `w1_therm` | DS18B20 28-000000d458dc found, 30.4-31.7 C, 30/30 reads OK |
| Buzzer | AXI GPIO bit 1 on W12 (NMOS, active high) | same GPIO | `gpio-beeper` (input device, evdev) | driver registered, tone command accepted; audibility not confirmed |
| Fan | AXI Timer PWM (pwm-xilinx), pin E15 inverted for the board's NMOS; tach G17 on GPIO bit 2 (edge interrupt) | 0xF8004000 | `pwm-fan` (hwmon) | pwm1 255 / 128 / 64 / 0 gave 5395 / - / 2111 / 0 rpm; default after boot 6093 rpm |

Findings
- The part is an **MS5607**, not the MS5611 in the schematic notes: the MS5611 formula gave half the pressure, the MS5607 formula gives ambient pressure.
  The vendor tutorial also says MS5607. The two share the command set (reset 0x1E, PROM 0xA0-0xAE, convert, read ADC) and differ in the compensation coefficients.
- The fan wire is driven through an NMOS (inverting): pwm-xilinx cannot invert, so `soc_top.v` inverts the timer output. Duty 0 stops the fan (it does not fall back to a minimum).
- Fan tach and DS18B20 bit-banging (30/30 reads) work despite ~190 ns per MMIO access.
- Bank 67 (fan) must be at VADJ 1.8 V; bank 86 (barometer, DS18B20, buzzer) is 3.3 V.
- Regression with these changes: 16/16 boots detect the SD card and reach login; Ethernet 38.6 Mb/s RX (unchanged), CRC errors 0.
- Not tested: pressure accuracy against a reference, fan behavior under a thermal governor (no thermal zone is defined), buzzer volume or frequency range, sensor behavior
  over a long run.
