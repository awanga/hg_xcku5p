#!/bin/bash
# SPDX-License-Identifier: MIT
# Verify the Vivado install, license, and XCKU5P device support with a trivial full-flow build.
# Usage: VIVADO_SETTINGS=/opt/Xilinx/2026.1/Vivado/settings64.sh scripts/check-env.sh
set -eu
: "${VIVADO_SETTINGS:=/opt/Xilinx/2026.1/Vivado/settings64.sh}"
# shellcheck source=/dev/null
. "$VIVADO_SETTINGS"
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
vivado -mode batch -nojournal -log check.log -source "$here/fpga/scripts/check_vivado.tcl" >check.out 2>&1 || {
	tail -5 check.out
	echo "check-env: FAIL" >&2
	exit 1
}
grep -q CHECK_VIVADO_PASS check.log
grep -E '^(VIVADO_VERSION|PART_FOUND)' check.log
echo "check-env: PASS"
