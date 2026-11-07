#!/bin/sh
# Restore the vendor demo into the config flash (erases and overwrites the first 16 MiB).
# Usage: factory/restore.sh   (board powered, FT232H JTAG attached; adapter flakiness: see docs/validation/flash-boot.md)
set -e
d=$(dirname "$0")
img=$(mktemp)
trap 'rm -f "$img"' EXIT
xz -dc "$d/vendor_flash_16MiB.bin.xz" > "$img"
(cd "$(dirname "$img")" && echo "$(cut -d' ' -f1 "$OLDPWD/$d/vendor_flash_16MiB.sha256")  $(basename "$img")" | sha256sum -c -)
openFPGALoader --cable ft232 --freq 3000000 --fpga-part xcku5p-ffvb676 -f --verify --unprotect-flash -o 0 --file-type bin "$img"
