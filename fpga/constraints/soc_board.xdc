# SPDX-License-Identifier: MIT
# Board I/O and clocks for the minimal SoC (soc_top). DDR4 pins are in ddr4_pins.xdc, key/LED/UART TX in bringup_board.xdc.
# clk50 is constrained in bringup_board.xdc
# UART1 PC->FPGA (CP2105 SCI)
set_property PACKAGE_PIN H16 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_rx]
# Asynchronous reset assertion from DDR4 calibration (ui_clk) into the CPU reset synchroniser, and the status
# synchronisers in soc_regs, are clock-domain crossings handled in RTL.
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *cpu_rst_q_reg[*]/CLR}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_regs/key_s_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_regs/calib_s_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_regs/rst_s_reg[0]/D}]
# Slow inputs and outputs
set_false_path -from [get_ports uart_rx]
set_false_path -to [get_ports {led[*] uart_tx}]
