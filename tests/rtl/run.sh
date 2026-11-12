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
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
