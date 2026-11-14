#!/bin/bash
# SPDX-License-Identifier: MIT
# L2 cache study: run fw/membench on each generated SoC netlist in Verilator with a DDR-like memory model
# (read latency LAT cycles, one 256-bit beat per GAP+1 cycles). Output: build/soc_sim/l2/<soc>.txt (membench lines).
# usage: l2_sweep.sh <lat> <gap> <soc_name>...
set -u
here=$(cd "$(dirname "$0")/../../../.." && pwd)
lat=$1 gap=$2
shift 2
make -s -C "$here/fw/membench" BUILD=build_sweep >/dev/null 2>&1 || { echo "membench build failed"; exit 1; }
out=$here/build/soc_sim/l2
mkdir -p "$out"
for soc in "$@"; do
	defs=""
	case "$soc" in *dma*|*l2*) defs="-DWITH_DMA";; esac
	d=$out/obj_${soc}
	verilator --binary --timing -Wno-fatal -Wno-lint -O1 --top-module tb_soc -DSOC_MODULE=$soc $defs \
		-GLAT="$lat" -GGAP="$gap" -GROM_INIT="\"$here/fw/membench/build_sweep/membench_rom.hex\"" --Mdir "$d" \
		"$here/tests/soc/tb_soc.v" "$here/build/soc/$soc/$soc.v" "$here/fpga/rtl/vexii_ram.v" \
		"$here/fpga/rtl/axil_simple.v" "$here/fpga/rtl/boot_rom.v" "$here/fpga/rtl/soc_regs.v" >"$out/${soc}.build.log" 2>&1 || {
		echo "FAIL $soc build"; continue; }
	timeout 7200 "$d/Vtb_soc" | grep -E "^MB |TBRESULT" >"$out/${soc}_lat${lat}_gap${gap}.txt"
	echo "$soc lat=$lat gap=$gap: $(grep -c '^MB ' "$out/${soc}_lat${lat}_gap${gap}.txt") sizes, $(grep TBRESULT "$out/${soc}_lat${lat}_gap${gap}.txt" | cut -c1-60)"
done
