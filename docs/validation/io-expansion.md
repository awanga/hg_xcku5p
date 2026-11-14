# LEDs, keys, switches, I2C and the UART interrupt fix (2026-11-12)

Evidence: **board**. Bitstream `build/soc/vv_io2` (default SoC netlist `soc_l2u_128k_w4`; WNS +0.008 ns, WHS +0.010 ns, 23589 LUT, 28933 FF, 44.5 BRAM, 4 URAM, DRC 82 warnings and 2 advisories,
no errors; `tools/build_report.py`). Versus `vv_l2e128`: +911 LUT. Loaded over JTAG; Linux 6.18.59 with an initramfs payload (`linux/kernel/configure.sh` plus the new drivers),
loaded with `tools/load.py`. The config flash still holds `vv_l2e128` and the SD card still holds the older kernel: neither was rewritten (see "Not done").

## What was added
- AXI GPIO widened from 3 to 19 bits (`fpga/rtl/board_gpio_map.v`): bits 3-10 LED0-7 (active high, outputs default off), 11-14 KEY_PL0-3, 15-18 SW1-SW4 (inputs, bank 65 at 1.2 V).
  LED pins are OR-ed with the board-register LED field (`soc_regs`), so boot firmware status still works. Device tree: `gpio-leds`, `gpio-keys-polled` (20 ms, also debounces).
  K1 is also the SoC reset (it resets the DDR4 controller and holds the CPU in reset), so Linux only ever reads it released.
- Two AXI IIC masters (100 kHz): `i2c0` at 0xF8006000 (PL_I2C, AB14 SCL / W16 SDA, bank 84) and `i2c1` at 0xF8007000 (second bus, A9 SCL / B9 SDA, bank 86), PLIC sources 6 and 7;
  Linux `i2c-xiic`, `i2c-dev`; Buildroot `i2c-tools` and `evtest`. No EEPROM driver is bound; nothing was written to any EEPROM.
- Crossbar 8 -> 10 slaves, 7 PLIC inputs.

## Board results
| Check | Result |
|---|---|
| LED0-7 through `/sys/class/leds` | each brightness write moves exactly its GPIO bit (read back through the GPIO data register); the owner should confirm the LEDs light (not observable from here) |
| Keys K1-K4, SW1-SW4 idle | all read 0 with nothing pressed and the DIP switches in their current positions |
| I2C bus 1 (A9/B9) | `i2cdetect -y -r 1`: 0x50, 0x51, 0x58, 0x59. 0x50/0x51 are the two BL24C256 (U16, U25), the first 16 bytes read 0xFF (blank). 0x58/0x59 also answer reads with 0xFF; what they are is not known (read-only access, never written). The A9 = SCL / B9 = SDA order read from the schematic image is confirmed |
| I2C bus 0 (PL_I2C, AB14/W16) | no device answers between 0x03 and 0x77, the controller reports an idle bus. The schematic shows a BL24C02 (U4) with 2.2 k pull-ups to 3.3 V on these nets; either U4 is not fitted, or the pin order is swapped. Owner to check the board; not resolved |
| `tools/smoke.py --net 192.168.1.1` | 18 of 18 checks pass (and 2 of 18 fail when the expected kernel and CPU clock are altered in a copy, so the checks can fail) |
| Ethernet on the L2 image (iperf3 to the host, 10 s) | TX 72.0 Mb/s (0 retransmits), RX 41.3 Mb/s (3362 retransmits); `/proc/net/dev` shows 0 errors and 0 drops. The earlier non-L2 images measured 70 and 39-43 Mb/s, so the L2 changes nothing here |

Not tested: the physical keys and DIP switches (needs hands: run `evtest /dev/input/event0` on the board and press K2-K4 and flip SW1-SW4; the polarity is active high for the keys per the schematic, unknown for the DIP switches),
and the visible LEDs.

## UART console input hang (found and fixed)
Symptom: the console stopped accepting input; the board kept running (ping answered, kernel messages still appeared). With echo on it was rare; after `stty -echo`,
a back-to-back test of short commands (`tools/console_stress.py`: `echo B<i>` sent as soon as the previous answer arrived) completed 0, 32 and 51 of 400 on the L2 image.
Cause: the AMD UART Lite interrupt is a one-cycle pulse per event (`axi_uartlite_v2_0_rfs.vhd`: rising edge of RX data present, or TX FIFO empty). The PLIC gateway
generated for VexiiRiscv (`TilelinkPlic`) samples its source only while no earlier interrupt of that source awaits completion. A byte that arrives after the handler's last status read
raises its pulse inside that window; it is dropped, the byte stays in the RX FIFO, and nothing runs the handler again until a TX event (echo on supplies them).
Fix: `fpga/rtl/irq_hold.v` keeps the interrupt up until the CPU reads the UART status or receive register. `tests/rtl/tb_irq_hold.v` models the three parts and reproduces the loss
(pass-through delivers 18 of 3000 bytes, a hold that never clears storms, the fix delivers 3000 of 3000); on the board the reproducer completes 400 of 400 three times.
This is probably the cause of earlier "dead console" reports that were attributed to the interrupt synchronizer only (docs/validation/ethernet-bringup.md). The same pulse-into-level-gateway
pattern exists for the SPI interrupts (`irq_pulse`, deliberate there; the SD and barometer drivers have never been seen to stall on it) and was not changed.

Other findings while testing: a newline sent to the ROM during its 3 s window stops the SD boot and leaves the monitor prompt, so tools must not poke the console while the boot messages are still printing
(`tools/smoke.py` waits for 15 s of silence before sending anything).

## Not done
- Config flash and SD card are not updated: `build/linux/sdcard.img` (new kernel, device tree, rootfs with i2c-tools and evtest) is built but must be written by the owner (the whole image replaces the /data partition).
  The flash would take `vv_io2` through `fpga/scripts/flash_bit.tcl` once the owner approves overwriting it again.
- Physical key/switch/LED confirmation by the owner; EEPROM contents beyond the first 16 bytes; the unknown devices at 0x58/0x59; bus 0.
