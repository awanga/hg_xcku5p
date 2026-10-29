# 0005: SD card boot with persistent root filesystem

Status: proposed 2026-10-29 (feasibility investigation; implementation partly done, not yet run on a card).

## Context
Boot must come from the SD card (README) and the system needs persistent storage. The board's micro-SD socket is wired for 4-bit SD on bank 84
(3.3 V) with no card-detect or write-protect. There is no AMD SD controller IP in the catalogue; the CPU/UART loader works but takes ~4.5 min per boot.

## Findings (feasibility: yes)
- SD cards must support SPI mode. The pins map cleanly: CLK, CMD = MOSI, DAT0 = MISO, DAT3 = CS#. Mainline Linux has `spi-sifive` and `mmc_spi`
  (mmc-spi-slot binding); both are in the 6.18 tree used here. `fpga/rtl/spi_sifive.v` is register-compatible with the SiFive controller so no
  out-of-tree driver is needed. It is verified in simulation (independent slave model, mutants) and, with the ROM driver, against a behavioural SD card model.
- Boot and storage fit one card without conflict: sector 0 carries both the boot header (bytes 0..445, 112 bytes used) and the MBR partition table
  (bytes 446..509); sectors 1..32767 (16 MiB) hold OpenSBI, the kernel and the DTB as raw payloads read by the ROM; partition 1 (ext4, from 16 MiB)
  is the persistent root (`root=/dev/mmcblk0p1 rootwait rw`). `tools/mkcard.py` builds the image; `linux/dts/hg-xcku5p-sdroot.dts` selects the SD root.
  The SD-root kernel is 3.4 MB (no initramfs), the boot payload 3.8 MB.
- ROM boot: 3 s window for the UART monitor, then SD boot; a failed SD boot falls back to the monitor/UART loader, so a bad card never bricks the board.
- Throughput: SPI mode at 25 MHz is at most ~3 MB/s raw; the ROM driver does one AXI-Lite access per byte (estimate 0.2-0.5 MB/s, i.e. 10-20 s for the boot
  payload, not yet measured). Linux mmc_spi on spi-sifive is expected ~1-2 MB/s. Adequate for boot and a root filesystem; not for bulk data.

## Risks / limits
- SPI mode is slower than 4-bit SD (up to ~12 MB/s at 50 MHz); a native SD controller (e.g. LiteSDCard with the mainline `litex_mmc` driver, needing a DMA master
  into the coherent port) is the upgrade path if throughput matters. Keep the boot-area layout so the ROM stays valid.
- No card detect: the card is treated as non-removable; hot-swapping is unsupported.
- Power loss can corrupt a read-write ext4 root (ext4 journal limits damage). Options: read-only root with a tmpfs/overlay for writes, and a separate data partition.
- ROM and header format are a stable interface once cards exist; changes need a version field (not yet in the header).
- Not yet verified on hardware: the bitstream with the SPI master is building; a card must be written (dd of the image, destructive) by the user.
