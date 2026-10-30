#!/bin/bash
# SPDX-License-Identifier: MIT
# System test of the generated LiteEth GMII core on Verilator (Icarus hangs on the generated combinational NBAs), plus mutants.
# Needs build/liteeth/gateware/liteeth_core.v (fpga/scripts/gen_liteeth.sh, LiteEth pinned in docs/versions.md). The core is Verilated per variant (~35 s each).
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
b=$here/build/rtl_tests/liteeth
core=${1:-$here/build/liteeth/gateware/liteeth_core.v}
rm -rf "$b"; mkdir -p "$b"
fail=0

run() { # name core expect
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_liteeth --Mdir "$b/obj_$1" \
		"$here/tests/rtl/tb_liteeth.v" "$here/tests/rtl/sim_prims.v" "$2" >"$b/$1.build.log" 2>&1 || {
		echo "FAIL $1 (verilator build)"; tail -3 "$b/$1.build.log"; fail=1; return; }
	timeout 250 "$b/obj_$1/Vtb_liteeth" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [expect $3: $(grep TBRESULT "$b/$1.log" | cut -d' ' -f2-3)]" || {
		echo "FAIL $1 [expected $3]"; grep -E 'FAIL:|TBRESULT' "$b/$1.log" | head -3; fail=1; }
}

mut() { # name sed-expr
	sed "$2" "$core" >"$b/mut_$1.v"
	cmp -s "$core" "$b/mut_$1.v" && { echo "FAIL mutant $1 (sed did not change the core)"; fail=1; return; }
	run "mut_$1" "$b/mut_$1.v" FAIL
}

run core "$core" PASS
mut tx_bit0 's/^    gmii_tx_data <= maccore_ethphy_sink_payload_data;/    gmii_tx_data <= maccore_ethphy_sink_payload_data ^ 8'"'"'h01;/'
mut irq_dead 's/^assign interrupt = wishbone_interface_ev_irq;/assign interrupt = 1'"'"'b0;/'
mut crc_check_off 's/core_liteethmaccrc32checker_crc_error = (core_liteethmaccrc32checker_crc_crc_next != 32.d3338984827);/core_liteethmaccrc32checker_crc_error = 1'"'"'b0;/'
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
