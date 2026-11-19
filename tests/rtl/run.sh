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
sed 's/if (addr == 4.d0 \&\& wstrb\[0\]) led/if (addr == 4'"'"'d0) led/' "$sr" >"$b/mut_sr_strb.v"
cmp -s "$sr" "$b/mut_sr_strb.v" && { echo "FAIL mutant sr_strb unchanged"; fail=1; }
run_pe mut_sr_strb "$ai" "$b/mut_sr_strb.v" FAIL
sed 's/4.d2: rdata <= {30.d0, rst_s\[2\], calib_s\[2\]};/4'"'"'d2: rdata <= {30'"'"'d0, calib_s[2], rst_s[2]};/' "$sr" >"$b/mut_sr_status.v"
cmp -s "$sr" "$b/mut_sr_status.v" && { echo "FAIL mutant sr_status unchanged"; fail=1; }
run_pe mut_sr_status "$ai" "$b/mut_sr_status.v" FAIL
sed 's/rdata <= {16.d0, die_temp_in};/rdata <= {die_temp_in, 16'"'"'d0};/' "$sr" >"$b/mut_sr_temp.v"
cmp -s "$sr" "$b/mut_sr_temp.v" && { echo "FAIL mutant sr_temp unchanged"; fail=1; }
run_pe mut_sr_temp "$ai" "$b/mut_sr_temp.v" FAIL
sed 's/if (addr == 4.d9 \&\& wstrb\[0\]) ddr_half <= wdata\[0\];/if (addr == 4'"'"'d9) ddr_half <= wdata[0];/' "$sr" >"$b/mut_sr_half.v"
cmp -s "$sr" "$b/mut_sr_half.v" && { echo "FAIL mutant sr_half unchanged"; fail=1; }
run_pe mut_sr_half "$ai" "$b/mut_sr_half.v" FAIL
sed 's/4.d9: rdata <= {31.d0, ddr_half};/4'"'"'d9: rdata <= 32'"'"'d0;/' "$sr" >"$b/mut_sr_halfrd.v"
cmp -s "$sr" "$b/mut_sr_halfrd.v" && { echo "FAIL mutant sr_halfrd unchanged"; fail=1; }
run_pe mut_sr_halfrd "$ai" "$b/mut_sr_halfrd.v" FAIL
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
sed 's/if (!frame_tx_only \&\& rx_cnt != DEPTH)/if (!tx_only \&\& rx_cnt != DEPTH)/' "$sp" >"$b/mut_spi_txo.v"
cmp -s "$sp" "$b/mut_spi_txo.v" && { echo "FAIL mutant spi_txo unchanged"; fail=1; }
run_sp mut_spi_txo "$b/mut_spi_txo.v" FAIL
# clk_freq_meter
cf=$here/fpga/rtl/clk_freq_meter.v
tbc=$here/tests/rtl/tb_clk_freq_meter.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$cf" >"$b/lint_cf.log" 2>&1 && echo "PASS lint clk_freq_meter" || {
	echo "FAIL lint clk_freq_meter"; head "$b/lint_cf.log"; fail=1; }
run_cf() { # name dut expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbc" "$2" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 280 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_cf clk_freq_meter "$cf" PASS
sed 's/count <= cnt - snap0;/count <= cnt;/' "$cf" >"$b/mut_cf_diff.v"
cmp -s "$cf" "$b/mut_cf_diff.v" && { echo "FAIL mutant cf_diff unchanged"; fail=1; }
run_cf mut_cf_diff "$b/mut_cf_diff.v" FAIL
sed 's/wire gate = (ph == 2.d1);/wire gate = (ph == 2'"'"'d1) || (ph == 2'"'"'d2);/' "$cf" >"$b/mut_cf_gate.v"
cmp -s "$cf" "$b/mut_cf_gate.v" && { echo "FAIL mutant cf_gate unchanged"; fail=1; }
run_cf mut_cf_gate "$b/mut_cf_gate.v" FAIL
# irq_pulse
ip_=$here/fpga/rtl/irq_pulse.v
tbi=$here/tests/rtl/tb_irq_pulse.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$ip_" >"$b/lint_ip.log" 2>&1 && echo "PASS lint irq_pulse" || {
	echo "FAIL lint irq_pulse"; head "$b/lint_ip.log"; fail=1; }
run_ip() { # name dut expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbi" "$2" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 60 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_ip irq_pulse "$ip_" PASS
sed 's/assign pulse = (cnt != 3.d0);/assign pulse = level;/' "$ip_" >"$b/mut_ip_level.v"
cmp -s "$ip_" "$b/mut_ip_level.v" && { echo "FAIL mutant ip_level unchanged"; fail=1; }
run_ip mut_ip_level "$b/mut_ip_level.v" FAIL
sed 's/if (level \&\& !level_q) cnt/if (level) cnt/' "$ip_" >"$b/mut_ip_edge.v"
cmp -s "$ip_" "$b/mut_ip_edge.v" && { echo "FAIL mutant ip_edge unchanged"; fail=1; }
run_ip mut_ip_edge "$b/mut_ip_edge.v" FAIL
# irq_sync
isy=$here/fpga/rtl/irq_sync.v
tbi=$here/tests/rtl/tb_irq_sync.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$isy" >"$b/lint_isy.log" 2>&1 && echo "PASS lint irq_sync" || {
	echo "FAIL lint irq_sync"; head "$b/lint_isy.log"; fail=1; }
run_ip irq_sync "$isy" PASS
sed 's/s2 <= s1;/s2 <= d;/' "$isy" >"$b/mut_isy_one.v"
cmp -s "$isy" "$b/mut_isy_one.v" && { echo "FAIL mutant isy_one unchanged"; fail=1; }
run_ip mut_isy_one "$b/mut_isy_one.v" FAIL
sed 's/s1 <= d;/s1 <= {d[0], d[W-1:1]};/' "$isy" >"$b/mut_isy_rot.v"
cmp -s "$isy" "$b/mut_isy_rot.v" && { echo "FAIL mutant isy_rot unchanged"; fail=1; }
run_ip mut_isy_rot "$b/mut_isy_rot.v" FAIL
# gmii_rx_reg
grr=$here/fpga/rtl/gmii_rx_reg.v
tbi=$here/tests/rtl/tb_gmii_rx_reg.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$grr" >"$b/lint_grr.log" 2>&1 && echo "PASS lint gmii_rx_reg" || {
	echo "FAIL lint gmii_rx_reg"; head "$b/lint_grr.log"; fail=1; }
run_ip gmii_rx_reg "$grr" PASS
sed 's/assign q = r;/assign q = d;/' "$grr" >"$b/mut_grr_comb.v"
cmp -s "$grr" "$b/mut_grr_comb.v" && { echo "FAIL mutant grr_comb unchanged"; fail=1; }
run_ip mut_grr_comb "$b/mut_grr_comb.v" FAIL
sed 's/r <= d;/r <= {d[0], d[W-1:1]};/' "$grr" >"$b/mut_grr_rot.v"
cmp -s "$grr" "$b/mut_grr_rot.v" && { echo "FAIL mutant grr_rot unchanged"; fail=1; }
run_ip mut_grr_rot "$b/mut_grr_rot.v" FAIL
# drp_reader
drr=$here/fpga/rtl/drp_reader.v
tbi=$here/tests/rtl/tb_drp_reader.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$drr" >"$b/lint_drr.log" 2>&1 && echo "PASS lint drp_reader" || {
	echo "FAIL lint drp_reader"; head "$b/lint_drr.log"; fail=1; }
run_ip drp_reader "$drr" PASS
sed 's/end else if (&cnt) begin/end else if (cnt == 0) begin/' "$drr" >"$b/mut_drr_per.v"
cmp -s "$drr" "$b/mut_drr_per.v" && { echo "FAIL mutant drr_per unchanged"; fail=1; }
run_ip mut_drr_per "$b/mut_drr_per.v" FAIL
sed 's/busy <= 1.b1;/busy <= 1'"'"'b0;/' "$drr" >"$b/mut_drr_flood.v"
cmp -s "$drr" "$b/mut_drr_flood.v" && { echo "FAIL mutant drr_flood unchanged"; fail=1; }
run_ip mut_drr_flood "$b/mut_drr_flood.v" FAIL
sed 's/value <= do_in;/value <= 16'"'"'d0;/' "$drr" >"$b/mut_drr_val.v"
cmp -s "$drr" "$b/mut_drr_val.v" && { echo "FAIL mutant drr_val unchanged"; fail=1; }
run_ip mut_drr_val "$b/mut_drr_val.v" FAIL
# eth_addr_map
em=$here/fpga/rtl/eth_addr_map.v
tbm=$here/tests/rtl/tb_eth_addr_map.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$em" >"$b/lint_em.log" 2>&1 && echo "PASS lint eth_addr_map" || {
	echo "FAIL lint eth_addr_map"; head "$b/lint_em.log"; fail=1; }
run_em() { # name dut expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbm" "$2" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 60 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_em eth_addr_map "$em" PASS
sed 's/cpu_addr\[14\], 2.b00/cpu_addr[15], 2'"'"'b00/' "$em" >"$b/mut_em_bit.v"
cmp -s "$em" "$b/mut_em_bit.v" && { echo "FAIL mutant em_bit unchanged"; fail=1; }
run_em mut_em_bit "$b/mut_em_bit.v" FAIL
sed 's/15.b1111_1000_0000_001/15'"'"'b1111_1000_0000_000/' "$em" >"$b/mut_em_base.v"
cmp -s "$em" "$b/mut_em_base.v" && { echo "FAIL mutant em_base unchanged"; fail=1; }
run_em mut_em_base "$b/mut_em_base.v" FAIL

# ddr_halfmap
dhm=$here/fpga/rtl/ddr_halfmap.v
tbi=$here/tests/rtl/tb_ddr_halfmap.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$dhm" >"$b/lint_dhm.log" 2>&1 && echo "PASS lint ddr_halfmap" || {
	echo "FAIL lint ddr_halfmap"; head "$b/lint_dhm.log"; fail=1; }
run_ip ddr_halfmap "$dhm" PASS
sed 's/addr\[29:28\] == 2.b11/addr[29] == 1'"'"'b1/' "$dhm" >"$b/mut_dhm_win.v"
cmp -s "$dhm" "$b/mut_dhm_win.v" && { echo "FAIL mutant dhm_win unchanged"; fail=1; }
run_ip mut_dhm_win "$b/mut_dhm_win.v" FAIL
sed 's/{sel & (addr\[29:28\] == 2.b11), addr}/{sel, addr}/' "$dhm" >"$b/mut_dhm_all.v"
cmp -s "$dhm" "$b/mut_dhm_all.v" && { echo "FAIL mutant dhm_all unchanged"; fail=1; }
run_ip mut_dhm_all "$b/mut_dhm_all.v" FAIL
sed 's/{sel & (addr\[29:28\] == 2.b11), addr}/{sel \& (addr[29:28] == 2'"'"'b11), addr[28:0], addr[29]}/' "$dhm" >"$b/mut_dhm_rot.v"
cmp -s "$dhm" "$b/mut_dhm_rot.v" && { echo "FAIL mutant dhm_rot unchanged"; fail=1; }
run_ip mut_dhm_rot "$b/mut_dhm_rot.v" FAIL
# board_gpio_map
bgm=$here/fpga/rtl/board_gpio_map.v
tbi=$here/tests/rtl/tb_board_gpio_map.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$bgm" >"$b/lint_bgm.log" 2>&1 && echo "PASS lint board_gpio_map" || {
	echo "FAIL lint board_gpio_map"; head "$b/lint_bgm.log"; fail=1; }
run_ip board_gpio_map "$bgm" PASS
sed 's/assign led = gpio_o\[10:3\] & ~gpio_t\[10:3\];/assign led = gpio_o[10:3];/' "$bgm" >"$b/mut_bgm_tri.v"
cmp -s "$bgm" "$b/mut_bgm_tri.v" && { echo "FAIL mutant bgm_tri unchanged"; fail=1; }
run_ip mut_bgm_tri "$b/mut_bgm_tri.v" FAIL
sed 's/{sw, key, led, fan_fb, beep, ds18b20_i}/{key, sw, led, fan_fb, beep, ds18b20_i}/' "$bgm" >"$b/mut_bgm_swap.v"
cmp -s "$bgm" "$b/mut_bgm_swap.v" && { echo "FAIL mutant bgm_swap unchanged"; fail=1; }
run_ip mut_bgm_swap "$b/mut_bgm_swap.v" FAIL
sed 's/assign beep = gpio_o\[1\] & ~gpio_t\[1\];/assign beep = gpio_o[1];/' "$bgm" >"$b/mut_bgm_beep.v"
cmp -s "$bgm" "$b/mut_bgm_beep.v" && { echo "FAIL mutant bgm_beep unchanged"; fail=1; }
run_ip mut_bgm_beep "$b/mut_bgm_beep.v" FAIL
# irq_hold
ihd=$here/fpga/rtl/irq_hold.v
tbi=$here/tests/rtl/tb_irq_hold.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$ihd" >"$b/lint_ihd.log" 2>&1 && echo "PASS lint irq_hold" || {
	echo "FAIL lint irq_hold"; head "$b/lint_ihd.log"; fail=1; }
run_ip irq_hold "$ihd" PASS
sed 's/else if (clr) level <= 1.b0;//' "$ihd" >"$b/mut_ihd_noclr.v"
cmp -s "$ihd" "$b/mut_ihd_noclr.v" && { echo "FAIL mutant ihd_noclr unchanged"; fail=1; }
run_ip mut_ihd_noclr "$b/mut_ihd_noclr.v" FAIL
sed 's/else if (clr) level <= 1.b0;/else level <= 1'"'"'b0;/' "$ihd" >"$b/mut_ihd_pass.v"
cmp -s "$ihd" "$b/mut_ihd_pass.v" && { echo "FAIL mutant ihd_pass unchanged"; fail=1; }
run_ip mut_ihd_pass "$b/mut_ihd_pass.v" FAIL
# eth_dma
edm=$here/fpga/rtl/eth_dma.v
tbi=$here/tests/rtl/tb_eth_dma.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$edm" "$here/fpga/rtl/axil_simple.v" >"$b/lint_edm.log" 2>&1 && echo "PASS lint eth_dma" || {
	echo "FAIL lint eth_dma"; head "$b/lint_edm.log"; fail=1; }
run_dma() { # name dut expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbi" "$2" "$here/fpga/rtl/axil_simple.v" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 250 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_dma eth_dma "$edm" PASS
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_eth_dma --Mdir "$b/vl_edm" "$tbi" "$edm" "$here/fpga/rtl/axil_simple.v" >"$b/vl_edm.build.log" 2>&1 || {
	echo "FAIL eth_dma (verilator build)"; fail=1; }
timeout 250 "$b/vl_edm/Vtb_eth_dma" >"$b/vl_edm.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_edm.log" && echo "PASS eth_dma [verilator]" || { echo "FAIL eth_dma [verilator]"; fail=1; }
mut_dma() { # name sed-expression
	sed "$2" "$edm" >"$b/mut_$1.v"
	cmp -s "$edm" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_dma "mut_$1" "$b/mut_$1.v" FAIL
}
mut_dma edm_flush "s/(pos == 3.d7)/(pos == 3'd6)/"
mut_dma edm_arinc "s/m_araddr + 32.d4/m_araddr + 32'd8/"
mut_dma edm_bresp "s/if (m_bresp != 2.b00) begin/if (1'b0) begin/"
mut_dma edm_awinc "s/m_awaddr + 32.d8/m_awaddr + 32'd4/"
mut_dma edm_ien "s/assign irq = done \& ien;/assign irq = done;/"
mut_dma edm_busy "s/if (reg_we \&\& !busy \&\& reg_wstrb\[0\])/if (reg_we \&\& reg_wstrb[0])/"
# tmds_encoder
tme=$here/fpga/rtl/tmds_encoder.v
tbi=$here/tests/rtl/tb_tmds_encoder.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$tme" >"$b/lint_tme.log" 2>&1 && echo "PASS lint tmds_encoder" || {
	echo "FAIL lint tmds_encoder"; head "$b/lint_tme.log"; fail=1; }
run_ip tmds_encoder "$tme" PASS
mut_tme() { # name sed-expression
	sed "$2" "$tme" >"$b/mut_$1.v"
	cmp -s "$tme" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_ip "mut_$1" "$b/mut_$1.v" FAIL
}
mut_tme tme_noinv "s/(cnt > 6'sd0 \&\& diff > 6'sd0) || (cnt < 6'sd0 \&\& diff < 6'sd0)/1'b0/"
mut_tme tme_ctl "s/2'b01: q <= 10'b0010101011;/2'b01: q <= 10'b0010101010;/"
mut_tme tme_xnor "s/ || (n1d == 4'd4 \&\& d\[0\] == 1'b0)//"
# HDMI scan-out chain (timing, fetch, line buffer, encoders, serializers) in a shrunk mode, with an independent TMDS receiver model
hd=$here/fpga/rtl
hdmi_files="hdmi_out hdmi_timing hdmi_fetch hdmi_linebuf tmds_encoder tmds_ser axil_simple"
run_hdmi() { # name expect [mutated-file-basename mutated-path] [-P options...]
	local n=$1 want=$2 mb=${3:-} mp=${4:-} f list=""
	shift 4 2>/dev/null || shift $#
	for f in $hdmi_files; do
		if [ "$f" = "$mb" ]; then list="$list $mp"; else list="$list $hd/$f.v"; fi
	done
	iverilog -g2005 -o "$b/$n.vvp" "$@" "$here/tests/rtl/tb_hdmi_out.v" $list "$here/tests/rtl/sim_prims.v" >"$b/$n.build.log" 2>&1 || { echo "FAIL $n (build)"; fail=1; return; }
	timeout 250 vvp "$b/$n.vvp" >"$b/$n.log" 2>&1
	grep -q "TBRESULT.* $want\$" "$b/$n.log" && echo "PASS $n [icarus, expect $want]" || { echo "FAIL $n [expected $want]"; grep -E 'TBRESULT|FAIL' "$b/$n.log" | head -3; fail=1; }
}
for f in hdmi_out hdmi_timing hdmi_fetch hdmi_linebuf tmds_ser; do
	extra=()
	[ "$f" = hdmi_out ] && extra=("$hd/hdmi_timing.v" "$hd/hdmi_fetch.v" "$hd/hdmi_linebuf.v" "$hd/tmds_encoder.v" "$hd/tmds_ser.v" "$hd/axil_simple.v")
	verilator --lint-only -Wall -Wno-DECLFILENAME "$here/tests/rtl/sim_prims.v" "$hd/$f.v" "${extra[@]}" -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC >"$b/lint_$f.log" 2>&1 --top-module "$f" && echo "PASS lint $f" || { echo "FAIL lint $f"; head -5 "$b/lint_$f.log"; fail=1; }
done
run_hdmi hdmi_out PASS
hdmi_srcs=()
for f in $hdmi_files; do hdmi_srcs+=("$hd/$f.v"); done
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_hdmi_out --Mdir "$b/vl_hd" "$here/tests/rtl/tb_hdmi_out.v" \
	"${hdmi_srcs[@]}" "$here/tests/rtl/sim_prims.v" >"$b/vl_hd.build.log" 2>&1 || { echo "FAIL hdmi_out (verilator build)"; fail=1; }
timeout 250 "$b/vl_hd/Vtb_hdmi_out" >"$b/vl_hd.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_hd.log" && echo "PASS hdmi_out [verilator]" || { echo "FAIL hdmi_out [verilator]"; fail=1; }
run_hdmi hdmi_slow PASS "" "" -P tb_hdmi_out.LAT=30 -P tb_hdmi_out.GAP=2
run_hdmi hdmi_late PASS "" "" -P tb_hdmi_out.LAT=200 -P tb_hdmi_out.EXPECT_LATE=1
mut_hdmi() { # name file sed-expression
	sed "$3" "$hd/$2.v" >"$b/mut_$1.v"
	cmp -s "$hd/$2.v" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_hdmi "mut_$1" FAIL "$2" "$b/mut_$1.v"
}
mut_hdmi hd_lane hdmi_out "s/2'd1: pix <= lb_rdata\[31:16\];/2'd1: pix <= lb_rdata[47:32];/"
mut_hdmi hd_blue hdmi_out "s/b8 <= {pix\[4:0\], pix\[4:2\]};/b8 <= {pix[4:0], 3'b000};/"
mut_hdmi hd_hspol hdmi_timing "s/parameter HS_NEG = 1,/parameter HS_NEG = 0,/"
mut_hdmi hd_addr hdmi_fetch "s/base_q + line_no \* LINE_BYTES/base_q + line_no * (LINE_BYTES \/ 2)/"
mut_hdmi hd_bank hdmi_fetch "s/bank <= line_no\[0\];/bank <= ~line_no[0];/"
mut_hdmi hd_base hdmi_fetch "s/if (line_no == 10'd0) begin/if (1'b1) begin/"
mut_hdmi hd_ser tmds_ser "s/.D1(sh\[0\]), .D2(sh\[1\])/.D1(sh[1]), .D2(sh[0])/"
# pcie_regs (host/CPU shared registers of the PCIe endpoint)
prg=$here/fpga/rtl/pcie_regs.v
tbp=$here/tests/rtl/tb_pcie_regs.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$prg" "$here/fpga/rtl/axil_simple.v" >"$b/lint_prg.log" 2>&1 && echo "PASS lint pcie_regs" || {
	echo "FAIL lint pcie_regs"; head "$b/lint_prg.log"; fail=1; }
run_prg() { # name dut expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbp" "$2" "$here/fpga/rtl/axil_simple.v" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 250 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_prg pcie_regs "$prg" PASS
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_pcie_regs --Mdir "$b/vl_prg" "$tbp" "$prg" "$here/fpga/rtl/axil_simple.v" >"$b/vl_prg.build.log" 2>&1 || {
	echo "FAIL pcie_regs (verilator build)"; fail=1; }
timeout 250 "$b/vl_prg/Vtb_pcie_regs" >"$b/vl_prg.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_prg.log" && echo "PASS pcie_regs [verilator]" || { echo "FAIL pcie_regs [verilator]"; fail=1; }
mut_prg() { # name sed-expression
	sed "$2" "$prg" >"$b/mut_$1.v"
	cmp -s "$prg" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_prg "mut_$1" "$b/mut_$1.v" FAIL
}
mut_prg prg_setwins "s/host_db <= (host_db \& ~(c_db_clr ? c_wd : 32'd0)) | (h_db_set ? h_wd : 32'd0);/host_db <= (host_db | (h_db_set ? h_wd : 32'd0)) \& ~(c_db_clr ? c_wd : 32'd0);/"
mut_prg prg_hostien "s/if (c_we \&\& c_addr\[6:2\] == 5'd4) ien <= c_wd\[0\];/if ((c_we \&\& c_addr[6:2] == 5'd4) || (h_we \&\& h_addr[6:2] == 5'd4)) ien <= c_we ? c_wd[0] : h_wd[0];/"
mut_prg prg_noien "s/assign irq = ien \&\& (|host_db);/assign irq = |host_db;/"
mut_prg prg_hostwins "s/if (c_mb) mbox\[c_mi\] <= c_wd;//; s/if (h_mb) mbox\[h_mi\] <= h_wd;/if (c_mb) mbox[c_mi] <= c_wd;\n        if (h_mb) mbox[h_mi] <= h_wd;/"
mut_prg prg_rdcnt "s/if (h_re) host_rd <= host_rd + 32'd1;/if (h_re || c_re) host_rd <= host_rd + 32'd1;/"
mut_prg prg_wrcnt "s/if (h_we) host_wr <= host_wr + 32'd1;/if (h_we || c_we) host_wr <= host_wr + 32'd1;/"
mut_prg prg_alive "s/alive_cnt <= 16'hFFFF;/alive_cnt <= 16'h00FF;/"
mut_prg prg_hostwin "s/if (c_we \&\& c_addr\[6:2\] == 5'd29) wsize <= c_wd;/if (h_we \&\& h_addr[6:2] == 5'd29) wsize <= h_wd; if (c_we \&\& c_addr[6:2] == 5'd29) wsize <= c_wd;/"
mut_prg prg_hostrdwin "s/5'd29: rd = cpu ? wsize : 32'd0;/5'd29: rd = wsize;/"
mut_prg prg_winrst "s/            wsize <= 32'd0;\n//; s/wsize <= 32'd0;/wsize <= wsize;/"
mut_prg prg_sticky "s/else if (c_we \&\& c_addr\[6:2\] == 5'd1 \&\& c_wd\[5\]) ever_up <= 1'b0;/else ever_up <= 1'b0;/"
# vpcie (logical PCIe device of the CPU-as-root-complex variant)
vpd=$here/fpga/rtl/vpcie.v
tbv=$here/tests/rtl/tb_vpcie.v
vp_srcs=("$here/fpga/rtl/pcie_regs.v" "$here/fpga/rtl/axil_simple.v")
verilator --lint-only -Wall -Wno-DECLFILENAME "$vpd" >"$b/lint_vpd.log" 2>&1 && echo "PASS lint vpcie" || {
	echo "FAIL lint vpcie"; head "$b/lint_vpd.log"; fail=1; }
run_vpd() { # name dut expect [iverilog args]
	local n=$1 d=$2 e=$3
	shift 3
	iverilog -g2005 "$@" -o "$b/$n.vvp" "$tbv" "$d" "${vp_srcs[@]}" >"$b/$n.build.log" 2>&1 || { echo "FAIL $n (build)"; fail=1; return; }
	timeout 250 vvp "$b/$n.vvp" >"$b/$n.log" 2>&1
	grep -q "TBRESULT.* $e\$" "$b/$n.log" && echo "PASS $n [icarus, expect $e]" || { echo "FAIL $n [expected $e]"; grep -E 'TBRESULT|FAIL' "$b/$n.log" | head -3; fail=1; }
}
run_vpd vpcie "$vpd" PASS
run_vpd vpcie_slow "$vpd" PASS -P tb_vpcie.RDLY=3
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_vpcie --Mdir "$b/vl_vpd" "$tbv" "$vpd" "${vp_srcs[@]}" >"$b/vl_vpd.build.log" 2>&1 || {
	echo "FAIL vpcie (verilator build)"; fail=1; }
timeout 250 "$b/vl_vpd/Vtb_vpcie" >"$b/vl_vpd.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_vpd.log" && echo "PASS vpcie [verilator]" || { echo "FAIL vpcie [verilator]"; fail=1; }
mut_vpd() { # name sed-expression
	sed "$2" "$vpd" >"$b/mut_$1.v"
	cmp -s "$vpd" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_vpd "mut_$1" "$b/mut_$1.v" FAIL
}
mut_vpd vp_rmem "s/wire r_hit0   = ra\[20\] \&\& cmd_mem \&\&/wire r_hit0   = ra[20] \&\&/"
mut_vpd vp_wmem "s/wire w_hit0   = wa\[20\] \&\& cmd_mem \&\&/wire w_hit0   = wa[20] \&\&/"
mut_vpd vp_base "s/bar0 == {BASE\[31:21\], ra\[20:16\]}/bar0[4:0] == ra[20:16]/"
mut_vpd vp_abort "s/r_cfg_f0 ? cfg_q : 32'hFFFFFFFF/r_cfg_f0 ? cfg_q : 32'd0/"
mut_vpd vp_cmdstrb "s/if (wb\[1\]) cmd_intxd <= wd\[10\];/if (wb[0]) cmd_intxd <= wd[10];/"
mut_vpd vp_intxd "s/assign intx = intx_pending \& ~cmd_intxd;/assign intx = intx_pending;/"
mut_vpd vp_status "s/{12'd0, intx_pending, 3'd0,/{12'd0, intx, 3'd0,/"
mut_vpd vp_off "s/assign m_awaddr  = wa\[15:0\];/assign m_awaddr  = {10'd0, wa[5:0]};/"
mut_vpd vp_rst "s/            bar0 <= 16'd0;//"
mut_vpd vp_dev "s/(ra\[19:12\] == 8'd0)/(ra[19:15] == 5'd0)/"
mut_vpd vp_wdev "s/(wa\[19:12\] == 8'd0)/(wa[19:15] == 5'd0)/"
mut_vpd vp_bar "s/if (wb\[2\]) bar0\[7:0\] <= wd\[23:16\];/if (wb[2]) bar0[7:0] <= wd[23:16] \& 8'hFE;/"
mut_vpd vp_wsel "s/wsel <= !w_hit0;/wsel <= 1'b0;/"
mut_vpd vp_rsel "s/rsel <= !r_hit0;/rsel <= 1'b0;/"
mut_vpd vp_b1base "s/bar1 == {BASE\[31:21\], ra\[20:16\]}/bar1[4:0] == ra[20:16]/"
mut_vpd vp_b1wr "s/if (wb\[2\]) bar1\[7:0\] <= wd\[23:16\];/if (wb[2]) bar1[7:0] <= wd[23:16] \& 8'hFE;/"
mut_vpd vp_b1prio "s/wsel <= !w_hit0;/wsel <= w_hit1;/"
# vpcie_ep (vpcie + pcie_regs + vdma wired together: BAR routing, window, interrupts)
vpe=$here/fpga/rtl/vpcie_ep.v
tbpd=$here/tests/rtl/tb_vpcie_dma.v
vpe_srcs=("$here/fpga/rtl/vpcie.v" "$here/fpga/rtl/vdma.v" "$here/fpga/rtl/pcie_regs.v" "$here/fpga/rtl/axil_simple.v")
run_vpe() { # name dut expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbpd" "$2" "${vpe_srcs[@]}" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 250 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_vpe vpcie_ep "$vpe" PASS
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_vpcie_dma --Mdir "$b/vl_vpe" "$tbpd" "$vpe" "${vpe_srcs[@]}" >"$b/vl_vpe.build.log" 2>&1 || {
	echo "FAIL vpcie_ep (verilator build)"; fail=1; }
timeout 250 "$b/vl_vpe/Vtb_vpcie_dma" >"$b/vl_vpe.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_vpe.log" && echo "PASS vpcie_ep [verilator]" || { echo "FAIL vpcie_ep [verilator]"; fail=1; }
mut_vpe() { # name sed-expression
	sed "$2" "$vpe" >"$b/mut_$1.v"
	cmp -s "$vpe" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_vpe "mut_$1" "$b/mut_$1.v" FAIL
}
mut_vpe ep_rdata "s/assign v_rdata   = v_arsel ? d_rdata : h_rdata;/assign v_rdata   = h_rdata;/"
mut_vpe ep_wready "s/assign v_wready  = v_awsel ? d_wready : h_wready;/assign v_wready  = h_wready;/"
mut_vpe ep_intx "s/.intx_pending(dma_intx)/.intx_pending(cpu_db_any)/"
mut_vpe ep_win "s/.win_size(win_size), .user_req/.win_size(32'hFFFFFFFF), .user_req/"
mut_vpe ep_user "s/.user_req(cpu_db_any)/.user_req(1'b0)/"
# vdma (XDMA-compatible DMA subset of the logical root complex)
vdd=$here/fpga/rtl/vdma.v
tbd=$here/tests/rtl/tb_vdma.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$vdd" "$here/fpga/rtl/axil_simple.v" >"$b/lint_vdd.log" 2>&1 && echo "PASS lint vdma" || {
	echo "FAIL lint vdma"; head "$b/lint_vdd.log"; fail=1; }
run_vdd() { # name dut expect [iverilog args]
	local n=$1 d=$2 e=$3
	shift 3
	iverilog -g2005 "$@" -o "$b/$n.vvp" "$tbd" "$d" "$here/fpga/rtl/axil_simple.v" >"$b/$n.build.log" 2>&1 || { echo "FAIL $n (build)"; fail=1; return; }
	timeout 280 vvp "$b/$n.vvp" >"$b/$n.log" 2>&1
	grep -q "TBRESULT.* $e\$" "$b/$n.log" && echo "PASS $n [icarus, expect $e]" || { echo "FAIL $n [expected $e]"; grep -E 'TBRESULT|FAIL' "$b/$n.log" | head -3; fail=1; }
}
run_vdd vdma "$vdd" PASS
run_vdd vdma_slow "$vdd" PASS -P tb_vdma.LAT=2
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_vdma --Mdir "$b/vl_vdd" "$tbd" "$vdd" "$here/fpga/rtl/axil_simple.v" >"$b/vl_vdd.build.log" 2>&1 || {
	echo "FAIL vdma (verilator build)"; fail=1; }
timeout 280 "$b/vl_vdd/Vtb_vdma" >"$b/vl_vdd.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_vdd.log" && echo "PASS vdma [verilator]" || { echo "FAIL vdma [verilator]"; fail=1; }
mut_vdd() { # name sed-expression
	sed "$2" "$vdd" >"$b/mut_$1.v"
	cmp -s "$vdd" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_vdd "mut_$1" "$b/mut_$1.v" FAIL
}
mut_vdd vd_magic "s/(d0\[31:16\] == 16'hAD4B)/(d0[31:24] == 8'hAD)/"
mut_vdd vd_winend "s/(s_end <= w_end)/(s_end < w_end)/; s/(t_end <= w_end)/(t_end < w_end)/"
mut_vdd vd_winbase "s/(d2\[31:0\] >= win_base)/(d2[31:0] > win_base)/"
mut_vdd vd_winbase_s "s/(d1\[31:0\] >= win_base)/(d1[31:0] > win_base)/"
mut_vdd vd_srcside "s/(cur ? !s_win : 1'b0)/!s_win/"
mut_vdd vd_dstside "s/(cur ? 1'b0 : !t_win)/!t_win/"
mut_vdd vd_hisrc "s/host_src_hi || (cur/(cur/"
mut_vdd vd_hidst "s/host_dst_hi || (cur/(cur/"
mut_vdd vd_misal "s/|| (dlen\[2:0\] != 3'd0)//"
mut_vdd vd_4k "s/(s4k < d4k) ? s4k : d4k/s4k/"
mut_vdd vd_chunk "s/(m1 < 13'd128) ? m1 : 13'd128/(m1 < 13'd256) ? m1 : 13'd256/"
mut_vdd vd_count "s/cnt0 <= cnt0 + 32'd1/cnt0 <= cnt0 + 32'd2/"
mut_vdd vd_rc "s/(stl0 \& ~((rc_do \&\& !rc_ch) ? EV : 32'd0))/stl0/"
mut_vdd vd_cen "s/assign intx = (user_req \& uen\[0\]) | (|(creq \& cen));/assign intx = (user_req \& uen[0]) | (|creq);/"
mut_vdd vd_uen "s/assign intx = (user_req \& uen\[0\])/assign intx = (user_req)/"
mut_vdd vd_edge "s/if (ctl0\[0\] \&\& !run_q\[0\] \&\& !busy0)/if (ctl0[0] \&\& !busy0)/"
mut_vdd vd_next0 "s/ || d3 == 64'd0//"
mut_vdd vd_abort "s/ || !(cur ? ctl1\[0\] : ctl0\[0\])//"
mut_vdd vd_wrerr "s/if (m_bresp != 2'b00) begin/if (1'b0) begin/"
mut_vdd vd_rderr "s/if (rerr || m_rresp != 2'b00) begin/if (1'b0) begin/"
mut_vdd vd_descerr "s/if (rerr) begin/if (1'b0) begin/"
mut_vdd vd_arhi "s/(st == E_DAR \&\& dhi == 32'd0)/(st == E_DAR)/"
mut_vdd vd_lenz "s/end else if (dlen == 28'd0) begin/end else if (1'b0) begin/"
mut_vdd vd_cmpl "s/ev_bits <= (cmpl_b ? 32'h00000006 : 32'h00000002);/ev_bits <= 32'h00000002;/"
# axi_win (AXI4 window filter of the PCIe DMA master)
aw=$here/fpga/rtl/axi_win.v
tbw=$here/tests/rtl/tb_axi_win.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$aw" >"$b/lint_aw.log" 2>&1 && echo "PASS lint axi_win" || {
	echo "FAIL lint axi_win"; head "$b/lint_aw.log"; fail=1; }
run_aw() { # name dut stall expect
	iverilog -g2005 -o "$b/$1.vvp" -P tb_axi_win.STALL="$3" "$tbw" "$2" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 250 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $4\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $4]" || { echo "FAIL $1 [expected $4]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_aw axi_win_s0 "$aw" 0 PASS
run_aw axi_win_s1 "$aw" 1 PASS
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_axi_win --Mdir "$b/vl_aw" "$tbw" "$aw" >"$b/vl_aw.build.log" 2>&1 || {
	echo "FAIL axi_win (verilator build)"; fail=1; }
timeout 250 "$b/vl_aw/Vtb_axi_win" >"$b/vl_aw.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_aw.log" && echo "PASS axi_win [verilator]" || { echo "FAIL axi_win [verilator]"; fail=1; }
mut_aw() { # name sed-expression
	sed "$2" "$aw" >"$b/mut_$1.v"
	cmp -s "$aw" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_aw "mut_$1" "$b/mut_$1.v" 1 FAIL
}
mut_aw aw_end "s/({1'b0, win_size} >= w_end)/({1'b0, win_size} + 33'd1 >= w_end)/"
mut_aw aw_exact "s/({1'b0, win_size} >= w_end)/({1'b0, win_size} > w_end)/"
mut_aw aw_rend "s/({1'b0, win_size} >= r_end)/({1'b0, win_size} + 33'd1 >= r_end)/"
mut_aw aw_hi "s/w_ok <= !w_hi \&\& /w_ok <= /"
mut_aw aw_lo "s/w_ok <= !w_hi \&\& w_ge \&\& /w_ok <= !w_hi \&\& /"
mut_aw aw_rlo "s/r_ok <= !r_hi \&\& r_ge \&\& /r_ok <= !r_hi \&\& /"
mut_aw aw_decerr "s/localparam \[1:0\] DECERR = 2'b11;/localparam [1:0] DECERR = 2'b10;/"
mut_aw aw_rlast "s/s_rlast = (rcnt == elen);/s_rlast = (rcnt == elen + 8'd1);/"
mut_aw aw_rid "s/s_rid = eid;/s_rid = 4'd0;/"
mut_aw aw_drain "s/WX: if (s_wvalid \&\& s_wlast) wst <= WE;/WX: wst <= WE;/"
# cdc_cfg (configuration bus between clock domains), both speed ratios
cc=$here/fpga/rtl/cdc_cfg.v
tbc=$here/tests/rtl/tb_cdc_cfg.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$cc" >"$b/lint_cc.log" 2>&1 && echo "PASS lint cdc_cfg" || {
	echo "FAIL lint cdc_cfg"; head "$b/lint_cc.log"; fail=1; }
run_cc() { # name dut expect src_half dst_half
	iverilog -g2005 -o "$b/$1.vvp" -P tb_cdc_cfg.SRC_HALF="$4" -P tb_cdc_cfg.DST_HALF="$5" "$tbc" "$2" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 250 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -q "TBRESULT.* $3\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $3]" || { echo "FAIL $1 [expected $3]"; grep -E 'TBRESULT|FAIL' "$b/$1.log" | head -3; fail=1; }
}
run_cc cdc_cfg_fast_src "$cc" PASS 1500 5000
run_cc cdc_cfg_slow_src "$cc" PASS 5000 1500
mut_cc() { # name sed-expression
	sed "$2" "$cc" >"$b/mut_$1.v"
	cmp -s "$cc" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_cc "mut_$1" "$b/mut_$1.v" FAIL 1500 5000
}
mut_cc cc_busy "s/if (ack_s\[1\] == req) busy <= 1'b0;/if (ack_s[1] == req) busy <= 1'b1;/"
mut_cc cc_rst "s/            q <= {W{1'b0}};//"
mut_cc cc_noack "s/ack <= req_s\[1\];/ack <= ack;/"
# uart_rig (UART test rig of the CPU-less variant) with uart_rx and uart_tx
rg=$here/fpga/rtl/uart_rig.v
rx_=$here/fpga/rtl/uart_rx.v
tx_=$here/fpga/rtl/uart_tx.v
tbr=$here/tests/rtl/tb_uart_rig.v
verilator --lint-only -Wall -Wno-DECLFILENAME "$rg" "$rx_" "$tx_" >"$b/lint_rig.log" 2>&1 && echo "PASS lint uart_rig" || {
	echo "FAIL lint uart_rig"; head "$b/lint_rig.log"; fail=1; }
run_rg() { # name rig-file rx-file expect [iverilog args]
	local n=$1 d=$2 r=$3 e=$4
	shift 4
	iverilog -g2005 "$@" -o "$b/$n.vvp" "$tbr" "$d" "$r" "$tx_" >"$b/$n.build.log" 2>&1 || { echo "FAIL $n (build)"; fail=1; return; }
	timeout 280 vvp "$b/$n.vvp" >"$b/$n.log" 2>&1
	grep -aq "TBRESULT.* $e\$" "$b/$n.log" && echo "PASS $n [icarus, expect $e: $(grep -a TBRESULT "$b/$n.log" | cut -d' ' -f2-3)]" || {
		echo "FAIL $n [expected $e]"; grep -E 'TBRESULT|FAIL' "$b/$n.log" | head -3; fail=1; }
}
run_rg uart_rig "$rg" "$rx_" PASS
run_rg uart_rig_slow "$rg" "$rx_" PASS -P tb_uart_rig.LAT=9
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_uart_rig --Mdir "$b/vl_rig" "$tbr" "$rg" "$rx_" "$tx_" >"$b/vl_rig.build.log" 2>&1 || {
	echo "FAIL uart_rig (verilator build)"; fail=1; }
timeout 280 "$b/vl_rig/Vtb_uart_rig" >"$b/vl_rig.log" 2>&1
grep -q "TBRESULT.* PASS\$" "$b/vl_rig.log" && echo "PASS uart_rig [verilator]" || { echo "FAIL uart_rig [verilator]"; fail=1; }
mut_rg() { # name sed-expression
	sed "$2" "$rg" >"$b/mut_$1.v"
	cmp -s "$rg" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_rg "mut_$1" "$b/mut_$1.v" "$rx_" FAIL
}
mut_rx() { # name sed-expression
	sed "$2" "$rx_" >"$b/mut_$1.v"
	cmp -s "$rx_" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; }
	run_rg "mut_$1" "$rg" "$b/mut_$1.v" FAIL
}
mut_rg rg_lane "s/32'h0000000F << {addr\[4:2\], 2'b00}/32'h0000000F << {addr[3:2], 2'b00}/"
mut_rg rg_rlane "s/m_rdata >> {addr\[4:2\], 5'd0}/m_rdata >> {3'd0, 5'd0}/"
mut_rg rg_bresp "s/if (selm ? (m_bresp != 2'b00) : (p_bresp != 2'b00)) send_err;/if (selm ? 1'b0 : (p_bresp != 2'b00)) send_err;/"
mut_rg rg_rresp "s/if (selm ? (m_rresp != 2'b00) : (p_rresp != 2'b00)) send_err;/if (selm ? 1'b0 : (p_rresp != 2'b00)) send_err;/"
mut_rg rg_stride "s/wire \[31:0\] addr_n = addr + 32'd4;/wire [31:0] addr_n = addr + 32'd8;/; s/addr <= addr + 32'd4;/addr <= addr + 32'd8;/"
mut_rg rg_digits "s/nd < 4'd8/nd < 4'd9/"
mut_rg rg_busy "s/if (rxv \&\& !busy) begin/if (rxv) begin/"
mut_rg rg_case "s/cmd <= (rxd >= \"a\" \&\& rxd <= \"z\") ? rxd - 8'h20 : rxd;/cmd <= rxd;/"
mut_rg rg_win "s/if (a0\[31:30\] == 2'b01) begin aw_m <= 1'b1; w_m <= 1'b1; end/if (a0[31:30] == 2'b11) begin aw_m <= 1'b1; w_m <= 1'b1; end/"
mut_rg rg_align "s/\"R\": if (na == 2'd1 \&\& a0\[1:0\] == 2'b00)/\"R\": if (na == 2'd1)/"
mut_rg rg_zero "s/ \&\& a1 != 32'd0 \&\& a1 <= 32'hFFFF//"
mut_rg rg_cross "s/selm <= (addr_n\[31:30\] == 2'b01);//"
mut_rx rx_mid "s/cnt <= CLKS_PER_BIT \/ 2 - 1;/cnt <= CLKS_PER_BIT - 1;/"
mut_rx rx_stop "s/valid <= rs\[1\];/valid <= 1'b1;/"
mut_rx rx_glitch "s/else if (rs\[1\]) st <= S_IDLE;/else if (1'b0) st <= S_IDLE;/"

# ---- card_regs / user_regs (CPU-less PCIe card register blocks)
cr_=$here/fpga/rtl/card_regs.v
ur_=$here/fpga/rtl/user_regs.v
ip_=$here/fpga/rtl/user_ip.v
tbc=$here/tests/rtl/tb_card.v
run_cd() { # name card_regs.v user_regs.v expect
	iverilog -g2005 -o "$b/$1.vvp" "$tbc" "$2" "$3" "$ip_" "$ai" >"$b/$1.build.log" 2>&1 || { echo "FAIL $1 (build)"; fail=1; return; }
	timeout 120 vvp "$b/$1.vvp" >"$b/$1.log" 2>&1
	grep -aq "TBRESULT.* $4\$" "$b/$1.log" && echo "PASS $1 [icarus, expect $4: $(grep -a TBRESULT "$b/$1.log" | cut -d' ' -f2-3)]" || {
		echo "FAIL $1 [expected $4]"; grep -aE 'TBRESULT|MISMATCH' "$b/$1.log" | head -3; fail=1; }
}
verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-MULTITOP "$cr_" "$ur_" "$ip_" "$ai" >"$b/lint_card.log" 2>&1 && echo "PASS lint card" || {
	echo "FAIL lint card"; head "$b/lint_card.log"; fail=1; }
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME --top-module tb_card --Mdir "$b/vl_card" "$tbc" "$cr_" "$ur_" "$ip_" "$ai" >"$b/vl_card.build.log" 2>&1 &&
	"$b/vl_card/Vtb_card" >"$b/vl_card.log" 2>&1
grep -aq "TBRESULT.* PASS\$" "$b/vl_card.log" && echo "PASS card [verilator]" || { echo "FAIL card [verilator]"; fail=1; }
run_cd card "$cr_" "$ur_" PASS
mut_cd() { # name file(card|user|ip) sed-expression
	local f=$cr_; [ "$2" = user ] && f=$ur_; [ "$2" = ip ] && f=$ip_
	sed "$3" "$f" >"$b/mut_$1.v"
	cmp -s "$f" "$b/mut_$1.v" && { echo "FAIL mutant $1 unchanged"; fail=1; return; }
	if [ "$2" = ip ]; then iverilog -g2005 -o "$b/mut_$1.vvp" "$tbc" "$cr_" "$ur_" "$b/mut_$1.v" "$ai" >"$b/mut_$1.build.log" 2>&1 || { echo "FAIL mut_$1 (build)"; fail=1; return; }
		timeout 120 vvp "$b/mut_$1.vvp" >"$b/mut_$1.log" 2>&1
		grep -aq "TBRESULT.* FAIL\$" "$b/mut_$1.log" && echo "PASS mut_$1 [icarus, expect FAIL]" || { echo "FAIL mut_$1 [expected FAIL]"; fail=1; }
	elif [ "$2" = user ]; then run_cd "mut_$1" "$cr_" "$b/mut_$1.v" FAIL; else run_cd "mut_$1" "$b/mut_$1.v" "$ur_" FAIL; fi
}
mut_cd cd_ro card "s/10'h0B) begin/10'h0B || addr[11:2] == 10'h00) begin/"
mut_cd cd_strb card "s/if (wstrb\[1\]) scratch\[15:8\] <= wdata\[15:8\];/scratch[15:8] <= wdata[15:8];/"
mut_cd cd_sync card "s/10'h08: rdata <= {30'd0, key_s\[1\], calib_s\[1\]};/10'h08: rdata <= {30'd0, calib_s[1], key_s[1]};/"
mut_cd cd_sec card "s/tick == CLK_HZ - 32'd1/tick == CLK_HZ/"
mut_cd cd_led card "s/10'h0C \&\& wstrb\[0\]) led_q/10'h0C) led_q/"
mut_cd cd_rst card "s/            scratch <= 32'd0;/            scratch <= scratch;/"
mut_cd ud_kick user "s/^        kick <= 32'd0;//"
mut_cd ud_w1c user "s/events <= (events | event_in) \& ~wdata;/events <= wdata;/"
mut_cd ud_sts user "s/rdata <= sts\[32\*addr\[5:2\] +: 32\];/rdata <= sts[32*addr[4:1] +: 32];/"
mut_cd ud_irq user "s/assign irq = |(events \& ien);/assign irq = |events;/"
mut_cd ud_ctl user "s/if (wstrb\[i\]) ctl_q/ctl_q/"
mut_cd ip_echo ip "s/\.rdata(32'd0)/.rdata(wdata)/"
mut_cd ud_decode user "s/if (w < 10'd16) begin/if (w < 10'd17) begin/"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
