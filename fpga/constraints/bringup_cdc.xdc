# SPDX-License-Identifier: MIT
# Clock-domain crossings of ddr4_bringup_top between ui_clk and CLK_50M (status UART and ui_clk frequency counter).
set_false_path -to [get_cells {st_a_reg[*]}]
set_false_path -to [get_cells {gate_s_reg[*] clr_s_reg[*]}]
set_false_path -from [get_cells {ui_cnt_reg[*]}] -to [get_cells {freq_hz_reg[*]}]
