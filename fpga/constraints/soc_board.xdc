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
# micro-SD socket J8 used in SPI mode (bank 84, 3.3 V): CLK, CMD = MOSI, DAT0 = MISO, DAT3 = CS#. DAT1/DAT2 have board pull-ups, unused.
set_property PACKAGE_PIN AE15 [get_ports sd_clk]
set_property PACKAGE_PIN AD15 [get_ports sd_cmd]
set_property PACKAGE_PIN AF13 [get_ports sd_dat0]
set_property PACKAGE_PIN AF14 [get_ports sd_dat3]
set_property IOSTANDARD LVCMOS33 [get_ports {sd_clk sd_cmd sd_dat0 sd_dat3}]
set_property SLEW FAST [get_ports {sd_clk sd_cmd sd_dat3}]
set_property DRIVE 8 [get_ports {sd_clk sd_cmd sd_dat3}]
# SD signals are generated from per_clk and sampled by the card/controller at <= 25 MHz; no board-level timing is constrained here.
set_false_path -from [get_ports sd_dat0]
set_false_path -to [get_ports {sd_clk sd_cmd sd_dat3}]
