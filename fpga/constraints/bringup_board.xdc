# SPDX-License-Identifier: MIT
# Board I/O for the DDR4 bring-up design. Pins from docs/hardware/board-inventory.md (schematic).
set_property PACKAGE_PIN T19 [get_ports key_rst]
set_property IOSTANDARD LVCMOS12 [get_ports key_rst]
# LED0..LED4 (bank 67, VCCO = VADJ; the 1.8 V jumper position is required)
set_property PACKAGE_PIN E16 [get_ports {led[0]}]
set_property PACKAGE_PIN E17 [get_ports {led[1]}]
set_property PACKAGE_PIN F15 [get_ports {led[2]}]
set_property PACKAGE_PIN D15 [get_ports {led[3]}]
set_property PACKAGE_PIN B16 [get_ports {led[4]}]
set_property PACKAGE_PIN D18 [get_ports {led[5]}]
set_property PACKAGE_PIN G15 [get_ports {led[6]}]
set_property PACKAGE_PIN E22 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]
# UART1 FPGA->PC (CP2105 SCI)
set_property PACKAGE_PIN G16 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_tx]
