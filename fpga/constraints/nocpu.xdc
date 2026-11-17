# SPDX-License-Identifier: MIT
# UART2 (CP2105 ECI) for the UART test rig of the CPU-less variant (docs/hardware/board-inventory.md: bank 67, VCCO = VADJ, 1.8 V jumper required)
set_property PACKAGE_PIN H17 [get_ports uart2_rx]
set_property IOSTANDARD LVCMOS18 [get_ports uart2_rx]
set_property PACKAGE_PIN G19 [get_ports uart2_tx]
set_property IOSTANDARD LVCMOS18 [get_ports uart2_tx]
set_false_path -from [get_ports uart2_rx]
set_false_path -to [get_ports uart2_tx]
