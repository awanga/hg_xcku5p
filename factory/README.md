# Factory flash image

`vendor_flash_16MiB.bin.xz` is a dump of the vendor demo found in the config flash on 2026-11-07 (first 16 MiB; the flash is 128 Mb; the rest of the
32 MiB read aliases it). `restore.sh` writes it back (checksum in `vendor_flash_16MiB.sha256`) and was tested: erase, write and `--verify` passed,
then the SoC bitstream was flashed again.

The image is vendor material and this repository is public, so the `.xz` is gitignored and exists only in the owner's working tree
(also keep a copy elsewhere). Without it, a bare flash can be reprogrammed from `docs/validation/flash-boot.md`.
