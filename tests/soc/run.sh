#!/bin/bash
# SPDX-License-Identifier: MIT
# System simulation (Verilator) of a generated SoC netlist running the boot ROM firmware, plus a fault-injection check.
# usage: tests/soc/run.sh [soc_name]   (default soc_base; the netlist is build/soc/<soc_name>/<soc_name>.v)
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
soc=${1:-soc_base}
b=$here/build/soc_sim/$soc
mkdir -p "$b"
fail=0
make -s -C "$here/fw/boot" BUILD=build_sim DEFS=-DTEST_BYTES=65536 >"$b/fw.log" 2>&1 || { echo "FAIL firmware build"; tail -5 "$b/fw.log"; exit 1; }
defs=""
case "$soc" in *dma*|*l2*) defs="-DWITH_DMA";; esac

run() { # name corrupt
	local n=$1 c=$2
	verilator --binary --timing -Wno-fatal -Wno-lint -O1 --top-module tb_soc -DSOC_MODULE=$soc $defs \
		-GCORRUPT="$c" -GROM_INIT="\"$here/fw/boot/build_sim/boot_rom.hex\"" --Mdir "$b/obj_$n" \
		"$here/tests/soc/tb_soc.v" "$here/build/soc/$soc/$soc.v" "$here/fpga/rtl/vexii_ram.v" \
		"$here/fpga/rtl/axil_simple.v" "$here/fpga/rtl/boot_rom.v" "$here/fpga/rtl/soc_regs.v" >"$b/$n.build.log" 2>&1 || {
		echo "FAIL $n (verilator build)"; tail -5 "$b/$n.build.log"; fail=1; return 1; }
	timeout 1500 "$b/obj_$n/Vtb_soc" >"$b/$n.log" 2>&1
}

check() { # name pattern description
	grep -q -- "$2" "$b/$1.log" && echo "  ok   $3" || { echo "  FAIL $3"; fail=1; }
}

run clean 0 || exit 1
echo "soc sim $soc: clean run"
check clean "HG-XCKU5P minimal SoC" "banner"
check clean "CPU clock: 400000 kHz" "CPU_KHZ register read through ROM-run firmware"
check clean "DDR4 calibrated: 1" "STATUS register"
check clean "TBRESULT.* PASS" "two error-free passes (no watchdog)"
grep -q "mismatch" "$b/clean.log" && { echo "  FAIL mismatch reported"; fail=1; }

# Fault injection: one corrupted read beat must be reported by the firmware (the test must be able to fail).
run corrupt 3000 || exit 1
echo "soc sim $soc: corrupted memory read beat"
check corrupt "mismatch @" "firmware reports mismatch"
[ "$fail" = 0 ] && echo "SOC SIM PASS" || echo "SOC SIM FAIL"
exit "$fail"
