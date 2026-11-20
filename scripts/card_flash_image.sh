#!/bin/bash
# SPDX-License-Identifier: MIT
# Makes the flash image of a PCIe card build and checks what a flash boot needs to enumerate on a host. Never writes the flash.
# usage: scripts/card_flash_image.sh <routed.dcp> <out.bit> [configrate_mhz]
#   1. fpga/scripts/flash_bit.tcl writes the SPIx4, compressed image (default 51 MHz, the verified rate).
#   2. tools/cfg_time.py estimates the configuration time against the 100 ms PCIe budget.
#   3. prints the programming command; run it yourself after approving the write (docs/validation/pcie-flash-enumeration.md).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 2 ] && [ $# -le 3 ] || { echo "usage: $0 <routed.dcp> <out.bit> [configrate_mhz]" >&2; exit 2; }
dcp=$1
out=$2
rate=${3:-51}
[ -f "$dcp" ] || { echo "missing $dcp" >&2; exit 1; }
# shellcheck disable=SC1091
command -v vivado >/dev/null || source /opt/Xilinx/2026.1/Vivado/settings64.sh
log="${out%.bit}.log"
vivado -mode batch -nojournal -log "$log" -source "$here/fpga/scripts/flash_bit.tcl" -tclargs "$dcp" "$out" "$rate" >/dev/null
[ -s "$out" ] || { echo "no image written, see $log" >&2; exit 1; }
python3 "$here/tools/pcie_identity.py" show
python3 "$here/tools/cfg_time.py" "$out" --rate "$rate"
echo "Image: $out"
echo "Write (flash erase and write need the owner's approval):"
echo "  openFPGALoader --cable ft232 --freq 3000000 --fpga-part xcku5p-ffvb676 -f --verify --unprotect-flash $out"
echo "Then power-cycle the host, and on it: python3 tools/pcie_identity.py check-lspci"
