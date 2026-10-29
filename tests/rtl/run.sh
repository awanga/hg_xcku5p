#!/bin/bash
# SPDX-License-Identifier: MIT
# Unit tests for fpga/rtl on Icarus and Verilator, plus DUT mutants that the testbench must catch.
# Build dirs are gitignored. Exit nonzero on any failure.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
b=$here/build/rtl_tests
rm -rf "$b"
mkdir -p "$b"
fail=0
rtl=$here/fpga/rtl/axi_memtest.v
tb=$here/tests/rtl/tb_axi_memtest.v

run_iv() { # name dut fault stall expect
	local n=$1 dut=$2 f=$3 s=$4 want=$5
	iverilog -g2005 -Wall -o "$b/$n.vvp" -P tb_axi_memtest.FAULT="$f" -P tb_axi_memtest.STALL="$s" "$tb" "$dut" >"$b/$n.build.log" 2>&1 || {
		echo "FAIL $n (iverilog build)"; fail=1; return; }
	timeout 300 vvp "$b/$n.vvp" >"$b/$n.log" 2>&1
	grep -q "TBRESULT.* $want\$" "$b/$n.log" && echo "PASS $n [icarus: $(grep TBRESULT "$b/$n.log" | cut -d' ' -f2-5)]" || {
		echo "FAIL $n [icarus expected $want]"; grep -E 'TBRESULT|MISMATCH|PROTOCOL' "$b/$n.log" | head -3; fail=1; }
}

run_vl() { # name fault stall
	local n=$1 f=$2 s=$3
	verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME -GFAULT="$f" -GSTALL="$s" --top-module tb_axi_memtest \
		--Mdir "$b/vl_$n" "$tb" "$rtl" >"$b/vl_$n.build.log" 2>&1 || {
		echo "FAIL $n (verilator build)"; tail -5 "$b/vl_$n.build.log"; fail=1; return; }
	timeout 300 "$b/vl_$n/Vtb_axi_memtest" >"$b/vl_$n.log" 2>&1
	grep -q "TBRESULT.* PASS\$" "$b/vl_$n.log" && echo "PASS $n [verilator]" || {
		echo "FAIL $n [verilator]"; grep -E 'TBRESULT' "$b/vl_$n.log"; fail=1; }
}

verilator --lint-only -Wall -Wno-DECLFILENAME "$rtl" >"$b/lint.log" 2>&1 && echo "PASS lint axi_memtest" || {
	echo "FAIL lint axi_memtest"; head "$b/lint.log"; fail=1; }

for f in 0 1 2 3 4 5 6; do
	for s in 0 1; do
		[ "$f" = 3 ] && [ "$s" = 0 ] && continue
		run_iv "f${f}_s${s}" "$rtl" "$f" "$s" PASS
	done
	run_vl "f${f}_s1" "$f" 1
done

# Mutants: the DUT is broken on purpose; the testbench must report FAIL.
mut() { # name sed-expr fault
	sed "$2" "$rtl" >"$b/mut_$1.v"
	cmp -s "$rtl" "$b/mut_$1.v" && { echo "FAIL mutant $1 (sed did not change the RTL)"; fail=1; return; }
	run_iv "mut_$1" "$b/mut_$1.v" "$3" 1 FAIL
}
mut cmp_low_half 's/(rdata != pattern(gbeat_r, key))/(((rdata ^ pattern(gbeat_r, key)) \& {128'"'"'d0, {128{1'"'"'b1}}}) != 256'"'"'d0)/' 1
mut ignore_rresp 's/ || (rresp != 2.b00)//' 6
mut key_not_advanced 's/key <= key + 32.h9E3779B9;/key <= key;/' 0
mut no_timeout 's/if (busy \&\& \&wd) begin/if (1'"'"'b0) begin/' 3

# status_uart + uart_tx
su=$here/fpga/rtl/status_uart.v
ut=$here/fpga/rtl/uart_tx.v
tbu=$here/tests/rtl/tb_status_uart.v
run_su() { # name status_uart.v uart_tx.v expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbu" "$2" "$3" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 120 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $4\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $4]" || { echo "FAIL $1 [expected $4]"; grep TBRESULT "$b/$1.log"; fail=1; }
}
for f in "$su" "$ut"; do
	verilator --lint-only -Wall -Wno-DECLFILENAME "$su" "$ut" >"$b/lint_su.log" 2>&1 || { echo "FAIL lint status_uart"; head "$b/lint_su.log"; fail=1; }
	break
done
run_su status_uart "$su" "$ut" PASS
sed 's/6.d13: ch = "E";/6'"'"'d13: ch = "F";/' "$su" >"$b/mut_su_letter.v"
cmp -s "$su" "$b/mut_su_letter.v" && { echo "FAIL mutant su_letter unchanged"; fail=1; }
run_su mut_su_letter "$b/mut_su_letter.v" "$ut" FAIL
sed 's/v\[31 - 4 \* k -: 4\]/v[4 * k +: 4]/' "$su" >"$b/mut_su_nib.v"
cmp -s "$su" "$b/mut_su_nib.v" && { echo "FAIL mutant su_nib unchanged"; fail=1; }
run_su mut_su_nib "$b/mut_su_nib.v" "$ut" FAIL
sed 's/nbits <= 4.d10;/nbits <= 4'"'"'d9;/' "$ut" >"$b/mut_ut_stop.v"
cmp -s "$ut" "$b/mut_ut_stop.v" && { echo "FAIL mutant ut_stop unchanged"; fail=1; }
run_su mut_ut_stop "$su" "$b/mut_ut_stop.v" FAIL

# axil_simple + soc_regs + boot_rom
ai=$here/fpga/rtl/axil_simple.v
sr=$here/fpga/rtl/soc_regs.v
br=$here/fpga/rtl/boot_rom.v
tbp=$here/tests/rtl/tb_soc_periph.v
python3 "$here/tests/rtl/gen_rom.py" "$b/rom_test.hex"
verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-MULTITOP "$ai" "$sr" "$br" >"$b/lint_periph.log" 2>&1 && echo "PASS lint periph" || {
	echo "FAIL lint periph"; head "$b/lint_periph.log"; fail=1; }
run_pe() { # name axil_simple.v soc_regs.v expect
	(cd "$b" && iverilog -g2005 -o "$1.vvp" "$tbp" "$2" "$3" "$br" >"$1.build.log" 2>&1) || { echo "FAIL $1 (build)"; fail=1; return; }
	(cd "$b" && timeout 120 vvp "$1.vvp" >"$1.log" 2>&1)
	grep -q "TBRESULT.* $4\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $4]" || { echo "FAIL $1 [expected $4]"; grep -E 'TBRESULT|MISMATCH' "$b/$1.log" | head -3; fail=1; }
}
run_pe periph "$ai" "$sr" PASS
sed 's/if (addr == 3.d0 \&\& wstrb\[0\]) led/if (addr == 3'"'"'d0) led/' "$sr" >"$b/mut_sr_strb.v"
cmp -s "$sr" "$b/mut_sr_strb.v" && { echo "FAIL mutant sr_strb unchanged"; fail=1; }
run_pe mut_sr_strb "$ai" "$b/mut_sr_strb.v" FAIL
sed 's/3.d2: rdata <= {30.d0, rst_s\[2\], calib_s\[2\]};/3'"'"'d2: rdata <= {30'"'"'d0, calib_s[2], rst_s[2]};/' "$sr" >"$b/mut_sr_status.v"
cmp -s "$sr" "$b/mut_sr_status.v" && { echo "FAIL mutant sr_status unchanged"; fail=1; }
run_pe mut_sr_status "$ai" "$b/mut_sr_status.v" FAIL
sed 's/rdata_q  <= rdata;/rdata_q  <= 32'"'"'d0;/' "$ai" >"$b/mut_ai_rdata.v"
cmp -s "$ai" "$b/mut_ai_rdata.v" && { echo "FAIL mutant ai_rdata unchanged"; fail=1; }
run_pe mut_ai_rdata "$b/mut_ai_rdata.v" "$sr" FAIL

# spi_sifive
sp=$here/fpga/rtl/spi_sifive.v
tbs=$here/tests/rtl/tb_spi_sifive.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$sp" >"$b/lint_spi.log" 2>&1 && echo "PASS lint spi_sifive" || {
	echo "FAIL lint spi_sifive"; head "$b/lint_spi.log"; fail=1; }
run_sp() { # name dut expect
	iverilog -g2012 -o "$b/$1.vvp" "$tbs" "$2" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 300 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3: $(grep TBRESULT "$b/$1.log" | cut -d' ' -f2-3)]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL:' "$b/$1.log" | head -3; fail=1; }
}
run_sp spi "$sp" PASS
sed 's/if (!pha) rxreg <= lsb_first/if (pha) rxreg <= lsb_first/' "$sp" >"$b/mut_spi_edge.v"
cmp -s "$sp" "$b/mut_spi_edge.v" && { echo "FAIL mutant spi_edge unchanged"; fail=1; }
run_sp mut_spi_edge "$b/mut_spi_edge.v" FAIL
sed "s/(csmode == 2'd2) ||/(csmode == 2'd1) ||/" "$sp" >"$b/mut_spi_cs.v"
cmp -s "$sp" "$b/mut_spi_cs.v" && { echo "FAIL mutant spi_cs unchanged"; fail=1; }
run_sp mut_spi_cs "$b/mut_spi_cs.v" FAIL
sed 's/assign mosi = lsb_first ? shreg\[0\] : shreg\[7\];/assign mosi = shreg[7];/' "$sp" >"$b/mut_spi_lsb.v"
cmp -s "$sp" "$b/mut_spi_lsb.v" && { echo "FAIL mutant spi_lsb unchanged"; fail=1; }
run_sp mut_spi_lsb "$b/mut_spi_lsb.v" FAIL
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
