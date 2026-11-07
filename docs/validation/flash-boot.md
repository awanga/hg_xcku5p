# Configuration flash boot (2026-11-07)

Goal: the FPGA configures itself from the QSPI flash at power-up/PROG_B, with no JTAG load.

## Result
- Bitstream: vv_fan2 routed checkpoint (`soc_top_postroute_physopt.dcp`, WNS +0.012, WHS +0.010, identical in the flash build) rewritten by
  `fpga/scripts/flash_bit.tcl` with SPIx4, 51 MHz, compression, unused pins pulled up, CFGBVS GND, 1.8 V. Size 7.0 MB (compressed).
- Programmed with openFPGALoader 0.13.1 over the FT232H (spiOverJtag bridge `spiOverJtag_xcku5p-ffvb676`), erase + write + `--verify` passed.
- Check: loaded the older vv_per1 bitstream by JTAG (die-temperature register 0xF8001020 reads 0), then `openFPGALoader --cable ft232 -r`;
  the board reconfigured and the register reads 0x00009B64 (fan2 design) and Linux boots from the SD card. So the flash image configures the FPGA.
- Cold power-up (owner power cycle, no JTAG load): the fan came on, the console showed a fresh boot (uptime < 1 min) and the die-temperature register read 0x00009E9B. The M[2:0] straps work at power-up.
- The previous flash content (32 MiB dump, 98 non-blank 64 KiB blocks up to 6.4 MB: the vendor demo) is kept outside the repository.

## Findings
- **The flash is not the 256 Mb part in the docs.** JEDEC ID 0x20BB18 = Micron 1.8 V, 128 Mb (MT25QU128 class); the 32 MiB dump aliases the
  first 16 MiB onto the second. The owner-stated MT25QU256ABA1EW9 (ID 0x20BB19) is not what is fitted, or the board revision differs. Docs not yet changed; owner to confirm.
- openFPGALoader 0.13.1 identifies the part as `MT25/N25Q128_1_8V`; the image fits in the 16 MiB, so no 4-byte addressing is needed.
- The FT232H adapter wedged twice right after the erase step (`mpsse_write ... usb bulk write failed`) and the next run saw it dead until reset.
  `USBDEVFS_RESET` (python `fcntl.ioctl(fd, 0x5514)` on /dev/bus/usb/BBB/DDD, no root needed) revives it. The successful run used `--freq 3000000`.
  Root cause unknown (the 6 MHz run failed too, the first dump at 6 MHz worked).

## Procedure
1. `vivado -mode batch -source fpga/scripts/flash_bit.tcl -tclargs <routed.dcp> <out.bit>`
2. `openFPGALoader --cable ft232 --freq 3000000 --fpga-part xcku5p-ffvb676 -f --verify --unprotect-flash <out.bit>`
3. Power-cycle, or `openFPGALoader --cable ft232 -r` to reconfigure.
