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
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_clk eth_gtx_clk eth_rst_n eth_tx_en eth_tx_er eth_rx_dv eth_rx_er eth_txd[*] eth_rxd[*]}]
set_property SLEW FAST [get_ports {eth_gtx_clk eth_tx_en eth_tx_er eth_txd[*]}]
set_property DRIVE 12 [get_ports {eth_gtx_clk eth_tx_en eth_tx_er eth_txd[*]}]
# GTX_CLK and the TX domain use a 125 MHz clock from the SoC MMCM (CLKOUT1); the PHY's RX clock only clocks the RX domain. Synthesis
# reduces the core's ODDR (constant inputs) to the buffered 125 MHz clock driving the GTX_CLK output buffer.
create_clock -period 8.000 -name eth_rx_clk [get_ports eth_rx_clk]
create_generated_clock -name eth_gtx_clk -source [get_pins u_mmcm/CLKOUT1] -divide_by 1 [get_ports eth_gtx_clk]
# RTL8211EG GMII timing, from the Realtek datasheet GMII table as found in a search snippet (rev 1.5, Table 58; not the full document, confirm
# against the owner's copy): the PHY drives RXD/RX_DV/RX_ER with >= 2.5 ns setup and >= 0.5 ns hold around RXCLK (period 8 ns), so the data
# window at the pins is [0.5, 8 - 2.5] ns after the launching edge; the PHY needs TXD/TX_EN/TX_ER >= 2.0 ns setup and >= 0 ns hold to GTX_CLK.
# Board trace skew between clock and data is not included (traces assumed length-matched).
set_output_delay -clock eth_gtx_clk -max 2.000 [get_ports {eth_tx_en eth_tx_er eth_txd[*]}]
set_output_delay -clock eth_gtx_clk -min 0.000 [get_ports {eth_tx_en eth_tx_er eth_txd[*]}]
set_input_delay -clock eth_rx_clk -max 5.500 [get_ports {eth_rx_dv eth_rx_er eth_rxd[*]}]
set_input_delay -clock eth_rx_clk -min 0.500 [get_ports {eth_rx_dv eth_rx_er eth_rxd[*]}]
set_false_path -to [get_ports eth_rst_n]
# The MAC's per_clk side and the PHY clock domain only exchange data through LiteEth's own CDC FIFOs/event logic. Do not put ui_clk
# in a group with per_clk: a clock group is a false path and would override the set_max_delay/set_bus_skew of the cc_per clock converter.
set_clock_groups -asynchronous -group [get_clocks eth_rx_clk] -group [get_clocks -of_objects [get_nets per_clk]] \
    -group [get_clocks -of_objects [get_pins u_mmcm/CLKOUT1]]

# MS5611 barometer (SPI, bank 86, 3.3 V), DS18B20 (1-Wire with 4.7 k board pull-up) and buzzer (NMOS drive, active high) are in bank 86.
set_property PACKAGE_PIN B11 [get_ports ms_sclk]
set_property PACKAGE_PIN C11 [get_ports ms_mosi]
set_property PACKAGE_PIN A10 [get_ports ms_miso]
set_property PACKAGE_PIN B10 [get_ports ms_cs_n]
set_property PACKAGE_PIN W13 [get_ports ds18b20_io]
set_property PACKAGE_PIN W12 [get_ports beep]
set_property IOSTANDARD LVCMOS33 [get_ports {ms_sclk ms_mosi ms_miso ms_cs_n ds18b20_io beep}]
set_property SLEW FAST [get_ports {ms_sclk ms_mosi ms_cs_n}]
set_property DRIVE 8 [get_ports {ms_sclk ms_mosi ms_cs_n}]
# 4-wire fan: PWM E15 (through NMOS Q9) and tach G17 (clamped to 1.8 V on the board), bank 67 at VADJ = 1.8 V (the jumper the UART needs anyway).
set_property PACKAGE_PIN E15 [get_ports fan_pwm]
set_property PACKAGE_PIN G17 [get_ports fan_fb]
set_property IOSTANDARD LVCMOS18 [get_ports {fan_pwm fan_fb}]
# All of these are slow (<= 25 MHz SPI, kHz PWM and tach, microsecond 1-Wire timing) and generated from or sampled by per_clk logic.
set_false_path -from [get_ports {ms_miso ds18b20_io fan_fb}]
set_false_path -to [get_ports {ms_sclk ms_mosi ms_cs_n ds18b20_io beep fan_pwm}]

# Keys K2-K4 (KEY_PL1-3; K1 = key_rst) and DIP switches SW1-SW4: inputs in bank 65 (1.2 V), read by software, no timing relation to any clock.
set_property PACKAGE_PIN N22 [get_ports {key_k[1]}]
set_property PACKAGE_PIN N21 [get_ports {key_k[2]}]
set_property PACKAGE_PIN P19 [get_ports {key_k[3]}]
set_property PACKAGE_PIN N19 [get_ports {sw[0]}]
set_property PACKAGE_PIN N23 [get_ports {sw[1]}]
set_property PACKAGE_PIN R21 [get_ports {sw[2]}]
set_property PACKAGE_PIN R20 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS12 [get_ports {key_k[*] sw[*]}]
set_false_path -from [get_ports {key_k[*] sw[*]}]

# I2C (open drain, board pull-ups, 100 kHz from per_clk). PL_I2C (BL24C02) in bank 84, second bus (2 x BL24C256) in bank 86, both 3.3 V.
# The second bus pin order (A9 = SCL, B9 = SDA) was read from the schematic image and is confirmed by an i2cdetect on the board.
set_property PACKAGE_PIN AB14 [get_ports i2c0_scl]
set_property PACKAGE_PIN W16 [get_ports i2c0_sda]
set_property PACKAGE_PIN A9 [get_ports i2c1_scl]
set_property PACKAGE_PIN B9 [get_ports i2c1_sda]
set_property IOSTANDARD LVCMOS33 [get_ports {i2c0_scl i2c0_sda i2c1_scl i2c1_sda}]
set_false_path -from [get_ports {i2c0_scl i2c0_sda i2c1_scl i2c1_sda}]
set_false_path -to [get_ports {i2c0_scl i2c0_sda i2c1_scl i2c1_sda}]
