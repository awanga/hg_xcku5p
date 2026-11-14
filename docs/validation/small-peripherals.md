# Small peripherals: barometer, 1-Wire temperature, buzzer, fan (2026-11-06)

Bitstream `build/soc/vv_per1` (WNS +0.003 ns, WHS +0.010 ns, Ethernet RX domain +0.445 ns, no DRC violations), kernel 6.18.59 with the drivers below.
All use upstream drivers; the device-tree nodes are in `linux/dts/hg-xcku5p.dtsi`.

| Function | Hardware | Address / PLIC | Linux driver | Result on the board |
|---|---|---|---|---|
| Barometer | second `spi_sifive` master, pins B11 SCLK, C11 MOSI, A10 MISO, B10 CS (bank 86, 3.3 V) | 0xF8005000, source 4 | `spi-sifive` + IIO `ms5611`/`ms5607` | `meas,ms5607` reads 99.87 kPa, 33.6 C; with `meas,ms5611` it read 49.9 kPa (half) |
| Temperature | AXI GPIO bit 0 through an IOBUF on W13 (open drain, board pull-up) | 0xF8003000, source 5 | `w1-gpio` + `w1_therm` | DS18B20 28-000000d458dc found, 30.4-31.7 C, 30/30 reads OK |
| Buzzer | AXI GPIO bit 1 on W12 (NMOS, active high) | same GPIO | `gpio-beeper` (input device, evdev) | driver registered; owner heard it sound (2026-11-06; the test sent tone events and a rapid on/off toggle, which of them was audible was not recorded) |
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

## Fan governor and die temperature (vv_fan2, 2026-11-06)
- `fpga/rtl/drp_reader.v` reads the SYSMON temperature register (address 0, default mode) about every 0.65 ms into board register 0xF8001020
  (`soc_regs.v`); degC = code * 509.3140064 / 65536 - 280.2308787 (SYSMONE4 transfer function from memory; absolute accuracy of a degree or two is unverified).
  First reading 41.5 C with the fan stopped, DS18B20 37 C at the same time; 32 C after a reboot with the fan at full speed.
- `linux/rootfs/fan-governor` (installed in `/usr/sbin`, started by `/etc/init.d/S04fan`), policy changed 2026-11-12: stopped below 30 C; 30-45 C quiet ramp 38 -> 61 (15-24 %);
  45-65 C 77 -> 128 (30-50 %); 65-80 C 128 -> 217 (50-85 %); 80-85 C 217 -> 255; 255 from 85 C. The curve sees a temperature that follows a rise at once and a fall only once it is 4 C below the held value (then
  it trails the real temperature by 4 C); the duty rises at once and falls by at most 10 per 2 s cycle; an unreadable or implausible reading or the service stopping gives 255. Settings (HYST, STEP_DOWN, PERIOD)
  can be set in the environment or `/etc/default/fan-governor`, which is on the read-only root, so changing them needs a new image. `fan-governor -1` runs one cycle and applies it (it has no history, so no hysteresis).
- Board checks: idle sequence over 3 minutes was stopped (41-44 C) -> started at 45 C (2050 rpm at 77) -> cooled to 40 C -> ramped down to stop; `S04fan stop` gave pwm 255 / 6123 rpm;
  a bad temperature register gave 255; killing a governor with shifted thresholds gave 255 (trap); restart ramped down from 255 by 10 per cycle.
  The board checks above are from the earlier policy (stop below 40 C, 77 at 45 C); the new policy is verified on the host only until the next image runs on the board.
- Host tests: `tests/rootfs/run.sh` (252 checks against an independent policy model, 6 mutants detected); RTL: `tests/rtl/run.sh` covers drp_reader (3 mutants) and the register.
- Not tested: behaviour at high die temperature (no load that heats the die was run), the thermal framework (no kernel thermal zone: the governor is a userspace service),
  a governor killed with SIGKILL (fan stays at its last duty).
- Regression: 16/16 boots detect the SD card; Ethernet RX 38.4 Mb/s, 0 CRC errors.
