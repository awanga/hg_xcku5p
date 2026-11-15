# PCIe endpoint (build_soc.tcl -pcie): Gen3 x4 on GTY quad 224 / PCIE4 block X0Y0. Pins from docs/hardware/board-inventory.md (owner-confirmed pinout; the
# vendor example design uses the same lanes). The XDMA IP brings its own timing constraints for the core and the converters.
set_property PACKAGE_PIN AB7 [get_ports pcie_refclk_p]
set_property PACKAGE_PIN AB6 [get_ports pcie_refclk_n]
create_clock -name pcie_refclk -period 10.000 [get_ports pcie_refclk_p]
# lane i: RX pair (from the host) and TX pair (to the host); the N pins follow from the P pins
set_property PACKAGE_PIN AB2 [get_ports {pcie_rxp[0]}]
set_property PACKAGE_PIN AD2 [get_ports {pcie_rxp[1]}]
set_property PACKAGE_PIN AE4 [get_ports {pcie_rxp[2]}]
set_property PACKAGE_PIN AF2 [get_ports {pcie_rxp[3]}]
set_property PACKAGE_PIN AC5 [get_ports {pcie_txp[0]}]
set_property PACKAGE_PIN AD7 [get_ports {pcie_txp[1]}]
set_property PACKAGE_PIN AE9 [get_ports {pcie_txp[2]}]
set_property PACKAGE_PIN AF7 [get_ports {pcie_txp[3]}]
# PERST# (slot A11 through 1K, 3.3 V pull-up on the slot side) into bank 66 (VADJ, jumper at 1.8 V): out of spec for continuous clamp current, see
# docs/hardware/board-inventory.md. It is asynchronous: the core and pcie_regs synchronise it.
set_property PACKAGE_PIN F22 [get_ports pcie_perst_n]
set_property IOSTANDARD LVCMOS18 [get_ports pcie_perst_n]
set_false_path -from [get_ports pcie_perst_n]
# The PCIe clocks (reference clock and the clocks the core derives from it, among them the 250 MHz user clock axi_aclk) are asynchronous to the CPU
# and peripheral clocks. Every crossing is a converter IP (which carries its own constraints), cdc_cfg or a two-flop synchroniser (constrained below).
set pcie_clks [get_clocks -include_generated_clocks pcie_refclk]
set_clock_groups -asynchronous -group $pcie_clks -group [get_clocks -quiet {mmcm_clkout0 per_clk_raw}]
# cdc_cfg: the holding register is stable for several cycles before the toggle reaches the destination, so only a bound on the datapath delay is needed;
# the toggles go into ASYNC_REG synchronisers. (Plain commands only: this file does not allow Tcl control flow.)
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *u_cdc_win/hold_reg*}] -to [get_cells -hier -filter {NAME =~ *u_cdc_win/q_reg*}] 6.000
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *u_cdc_win/req_reg*}] -to [get_cells -hier -filter {NAME =~ *u_cdc_win/req_s_reg*}] 3.000
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *u_cdc_win/ack_reg*}] -to [get_cells -hier -filter {NAME =~ *u_cdc_win/ack_s_reg*}] 3.000
# status inputs of pcie_regs (link, user clock toggle, PERST#) and the doorbell level into the PCIe clock: two-flop synchronisers
set_false_path -to [get_cells -hier -filter {NAME =~ *u_regs/link_s_reg*}]
set_false_path -to [get_cells -hier -filter {NAME =~ *u_regs/tog_s_reg*}]
set_false_path -to [get_cells -hier -filter {NAME =~ *u_regs/perst_s_reg*}]
set_false_path -to [get_cells -hier -filter {NAME =~ *u_pcie/db_s_reg*}]
