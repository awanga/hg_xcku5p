# SPDX-License-Identifier: MIT
# Board I/O of the lean CPU-less PCIe card (card_top): 50 MHz clock, KEY_PL0 reset, user LEDs. DDR4 pins are in ddr4_pins.xdc, UART2 in nocpu.xdc,
# the edge connector in pcie.xdc. Pins as in bringup_board.xdc (no UART1, SD, Ethernet, HDMI, I2C, SPI, GPIO or fan in this build).
set_property PACKAGE_PIN T19 [get_ports key_rst]
set_property IOSTANDARD LVCMOS12 [get_ports key_rst]
set_property PACKAGE_PIN E16 [get_ports {led[0]}]
set_property PACKAGE_PIN E17 [get_ports {led[1]}]
set_property PACKAGE_PIN F15 [get_ports {led[2]}]
set_property PACKAGE_PIN D15 [get_ports {led[3]}]
set_property PACKAGE_PIN B16 [get_ports {led[4]}]
set_property PACKAGE_PIN D18 [get_ports {led[5]}]
set_property PACKAGE_PIN G15 [get_ports {led[6]}]
set_property PACKAGE_PIN E22 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]
set_property PACKAGE_PIN E18 [get_ports clk50]
set_property IOSTANDARD LVCMOS18 [get_ports clk50]
create_clock -name clk50 -period 20.000 [get_ports clk50]

# DDR4 calibration (ui_clk) into the reset synchroniser, and the card_regs status synchronisers, are crossings handled in RTL.
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *cpu_rst_q_reg[*]/CLR}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_cregs/calib_s_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_cregs/key_s_reg[0]/D}]
# PCIe host doorbell level from per_clk into the rig's interrupt vector (ui_clk): first stage of a two-flop synchroniser
set_false_path -to [get_pins u_irq_sync/s1_reg[*]/D]
set_false_path -to [get_ports {led[*]}]

# user_ip self-test engines (mem_probe): the first flop of each synchroniser between the register clock and the DDR4 user clock, the configuration words the
# engine samples at the start of a run (stable for many clocks before, software contract) and the results read after DONE (stable then)
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_probe/go_s_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_probe/clr_s_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_probe/busy_s_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_probe/done_s_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *u_probe/err_s_reg[0]/D}]
set_max_delay -datapath_only 3.0 -from [get_cells -hierarchical -filter {NAME =~ *u_probe/cfg_*_reg*}]
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -filter {NAME =~ *u_probe/res_mism_reg* || NAME =~ *u_probe/res_wr_reg* || NAME =~ *u_probe/res_rd_reg*}] -to [get_cells -hierarchical -filter {NAME =~ u_uip/rdata_reg*}]
# user interrupt requests in flight, back from the PCIe clock to the register clock (pcie_ep): first flop of the two-flop synchroniser
set_false_path -to [get_pins -hierarchical -filter {NAME =~ u_pcie/pend_s1_reg[*]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ u_pcie/seen_s1_reg[*]/D}]
# user interrupt levels from the register clock into the PCIe clock (irq_req): first flop of the synchroniser
set_false_path -to [get_pins -hierarchical -filter {NAME =~ u_pcie/*/s_reg[0]/D}]
