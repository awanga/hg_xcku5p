#!/bin/bash
# SPDX-License-Identifier: MIT
# Out-of-context place-and-route of a generated SoC netlist. usage: ooc_soc.sh <soc_name> <clk_ns> [io_pct]
# Needs Vivado on PATH. Output: build/soc/ooc/<name>_<clk_ns>ns.{log,*.rpt}; last log line is EXIT=<rc>.
set -u
here=$(cd "$(dirname "$0")" && pwd)
build=${BUILD:-$(cd "$here/../../.." && pwd)/build}
name=$1 ns=$2 io=${3:-0}
tag=${name}_${ns}ns
mkdir -p "$build/soc/ooc"
cd "$build/soc/ooc" || exit 1
vivado -mode batch -nojournal -nolog -source "$here/ooc_impl.tcl" \
    -tclargs "$tag" "$name" litex_clk "$ns" "$io" "$build/soc/ooc/$tag" "$build/soc/$name/$name.v" "$here/../../rtl/vexii_ram.v" >"$tag.log" 2>&1
echo "EXIT=$?" >>"$tag.log"
