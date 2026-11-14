#!/bin/bash
# SPDX-License-Identifier: MIT
# Validate the device tree against the Linux binding schemas (dt-validate from the dtschema package) and fail on any finding that is
# not listed in tests/dts/dtbs_check_baseline.txt (each baseline line is a known local extension or an unbound board/CPU compatible, see
# docs/validation/dtbs-check.md). Needs a pip venv with dtschema and the kernel source; not run in hosted CI (kernel clone too large).
# usage: tests/dts/dtbs_check.sh   (env: VENV=build/venv, LINUX=build/third_party/linux)
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
venv=${VENV:-$here/build/venv}
linux=${LINUX:-$here/build/third_party/linux}
b=$here/build/dts_tests
mkdir -p "$b"
[ -x "$venv/bin/dt-validate" ] || { python3 -m venv "$venv" && "$venv/bin/pip" install -q dtschema; }
"$venv/bin/dt-mk-schema" -j "$linux/Documentation/devicetree/bindings" >"$b/schema.json" 2>"$b/mk.err" || { echo "FAIL schema build"; exit 1; }
cpp -nostdinc -undef -x assembler-with-cpp -I"$here/linux/dts" "$here/linux/dts/hg-xcku5p-sdroot.dts" | dtc -I dts -O dtb -o "$b/sdroot.dtb" - || exit 1
"$venv/bin/dt-validate" -s "$b/schema.json" -m "$b/sdroot.dtb" 2>&1 | grep -E '^[^	 ].*: ' | sed 's/^[^:]*dtb: //' | sort -u >"$b/findings.txt"
new=$(comm -13 <(sort -u "$here/tests/dts/dtbs_check_baseline.txt") "$b/findings.txt")
if [ -n "$new" ]; then echo "FAIL new binding findings:"; echo "$new"; exit 1; fi
echo "PASS dtbs_check ($(wc -l <"$b/findings.txt") known findings)"
