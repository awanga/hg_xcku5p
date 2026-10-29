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
make -s -C "$here/fw/boot" BUILD=build_sim DEFS="-DTEST_BYTES=65536 -DTEST_PASSES=2" >"$b/fw.log" 2>&1 || { echo "FAIL firmware build"; tail -5 "$b/fw.log"; exit 1; }
defs=""
case "$soc" in *dma*|*l2*) defs="-DWITH_DMA";; esac

run() { # name corrupt [rx_hex]
	local n=$1 c=$2 rx=${3:-}
	verilator --binary --timing -Wno-fatal -Wno-lint -O1 --top-module tb_soc -DSOC_MODULE=$soc $defs \
		-GCORRUPT="$c" -GRX_HEX="\"$rx\"" -GROM_INIT="\"$here/fw/boot/build_sim/boot_rom.hex\"" --Mdir "$b/obj_$n" \
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

# Loader: load a program over the UART receive model, run it, and see it print and return to the ROM.
make -s -C "$here/fw/app" >"$b/app.log" 2>&1 || { echo "FAIL app build"; exit 1; }
python3 "$here/tools/load.py" --make-stream "$here/fw/app/build/hello.bin" "$b/hello_rx.hex"
run loader 0 "$b/hello_rx.hex" || exit 1
echo "soc sim $soc: UART loader session"
check loader "HELLO FROM APP" "loaded program ran and printed"
check loader "OK " "loader acknowledged the write with a checksum"
check loader "TBRESULT.* PASS" "no watchdog"
n=$(grep -c "HG-XCKU5P minimal SoC" "$b/loader.log")
[ "$n" -ge 2 ] && echo "  ok   program returned to the ROM (banner printed $n times)" || { echo "  FAIL program did not return to ROM"; fail=1; }

# Fault injection: one corrupted read beat must be reported by the firmware (the test must be able to fail).
run corrupt 3000 || exit 1
echo "soc sim $soc: corrupted memory read beat"
check corrupt "mismatch @" "firmware reports mismatch"
[ "$fail" = 0 ] && echo "SOC SIM PASS" || echo "SOC SIM FAIL"
exit "$fail"
