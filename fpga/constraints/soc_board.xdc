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

# RTL8211EG (U30) in GMII mode, bank 87 (3.3 V). Pins from docs/hardware/schematic-pin-extract.csv.
set_property PACKAGE_PIN D14 [get_ports eth_rx_clk]
set_property PACKAGE_PIN C13 [get_ports eth_tx_clk]
set_property PACKAGE_PIN E13 [get_ports eth_gtx_clk]
set_property PACKAGE_PIN D13 [get_ports eth_rst_n]
set_property PACKAGE_PIN F14 [get_ports eth_tx_en]
set_property PACKAGE_PIN A14 [get_ports eth_tx_er]
set_property PACKAGE_PIN H12 [get_ports eth_rx_dv]
set_property PACKAGE_PIN J12 [get_ports eth_rx_er]
set_property PACKAGE_PIN E12 [get_ports {eth_txd[0]}]
set_property PACKAGE_PIN F13 [get_ports {eth_txd[1]}]
set_property PACKAGE_PIN C14 [get_ports {eth_txd[2]}]
set_property PACKAGE_PIN C12 [get_ports {eth_txd[3]}]
set_property PACKAGE_PIN B12 [get_ports {eth_txd[4]}]
set_property PACKAGE_PIN A12 [get_ports {eth_txd[5]}]
set_property PACKAGE_PIN A13 [get_ports {eth_txd[6]}]
set_property PACKAGE_PIN B14 [get_ports {eth_txd[7]}]
set_property PACKAGE_PIN F12 [get_ports {eth_rxd[0]}]
set_property PACKAGE_PIN G14 [get_ports {eth_rxd[1]}]
set_property PACKAGE_PIN G12 [get_ports {eth_rxd[2]}]
set_property PACKAGE_PIN H14 [get_ports {eth_rxd[3]}]
set_property PACKAGE_PIN J15 [get_ports {eth_rxd[4]}]
set_property PACKAGE_PIN J14 [get_ports {eth_rxd[5]}]
set_property PACKAGE_PIN H13 [get_ports {eth_rxd[6]}]
set_property PACKAGE_PIN J13 [get_ports {eth_rxd[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_clk eth_tx_clk eth_gtx_clk eth_rst_n eth_tx_en eth_tx_er eth_rx_dv eth_rx_er eth_txd[*] eth_rxd[*]}]
set_property SLEW FAST [get_ports {eth_gtx_clk eth_tx_en eth_tx_er eth_txd[*]}]
set_property DRIVE 12 [get_ports {eth_gtx_clk eth_tx_en eth_tx_er eth_txd[*]}]
# The PHY's recovered 125 MHz RX clock also clocks the TX side (LiteEthPHYGMII drives GTX_CLK from it). Synthesis reduces the core's
# ODDR (constant inputs) to the buffered RX clock driving the GTX_CLK output buffer, so the forwarded clock is defined from the RX port.
create_clock -period 8.000 -name eth_rx_clk [get_ports eth_rx_clk]
create_generated_clock -name eth_gtx_clk -source [get_ports eth_rx_clk] -divide_by 1 [get_ports eth_gtx_clk]
# RTL8211EG GMII timing (datasheet-memory, not verified): TX data setup 2.0 ns / hold 0 ns to GTX_CLK; RX data valid within +-0.5 ns of RX_CLK.
set_output_delay -clock eth_gtx_clk -max 2.000 [get_ports {eth_tx_en eth_tx_er eth_txd[*]}]
set_output_delay -clock eth_gtx_clk -min 0.000 [get_ports {eth_tx_en eth_tx_er eth_txd[*]}]
set_input_delay -clock eth_rx_clk -max 0.500 [get_ports {eth_rx_dv eth_rx_er eth_rxd[*]}]
set_input_delay -clock eth_rx_clk -min -0.500 [get_ports {eth_rx_dv eth_rx_er eth_rxd[*]}]
set_false_path -to [get_ports eth_rst_n]
set_false_path -from [get_ports eth_tx_clk]
# The MAC's per_clk side and the PHY clock domain only exchange data through LiteEth's own CDC FIFOs/event logic. Do not put ui_clk
# in a group with per_clk: a clock group is a false path and would override the set_max_delay/set_bus_skew of the cc_per clock converter.
set_clock_groups -asynchronous -group [get_clocks {eth_rx_clk eth_gtx_clk}] -group [get_clocks -of_objects [get_nets per_clk]]
