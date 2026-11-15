# SPDX-License-Identifier: MIT
# Creates the PCIe endpoint IP (DMA/Bridge Subsystem for PCI Express, "XDMA") for the board's edge connector:
# Gen3 x4 on the PCIE4 block X0Y0 / GTY quad 224 (board-inventory.md: lanes AB2/AD2/AE4/AF2 RX, AC5/AD7/AE9/AF7 TX, refclk AB7/AB6 from the slot, PERST# F22).
# usage (inside a Vivado session with the part set): source xdma_ip.tcl; make_xdma <module_name> <ip_dir> [pipe_sim 0|1]
# BAR0 = 64 KiB AXI4-Lite master window (host registers), BAR1 = DMA registers (the IP places them), AXI4 memory-mapped master/DMA 128-bit at 250 MHz,
# one H2C and one C2H channel, 4 user interrupts, MSI (1 vector) and MSI-X off. The IP's PCIe vendor ID is the Xilinx default 0x10EE.
proc make_xdma {name dir {pipe 0}} {
    create_ip -name xdma -vendor xilinx.com -library ip -module_name $name -dir $dir
    set_property -dict [list \
        CONFIG.functional_mode DMA \
        CONFIG.mode_selection Advanced \
        CONFIG.pcie_blk_locn X0Y0 \
        CONFIG.pl_link_cap_max_link_width X4 \
        CONFIG.pl_link_cap_max_link_speed 8.0_GT/s \
        CONFIG.ref_clk_freq 100_MHz \
        CONFIG.axi_data_width 128_bit \
        CONFIG.axisten_freq 250 \
        CONFIG.axilite_master_en true \
        CONFIG.axilite_master_size 64 \
        CONFIG.axilite_master_scale Kilobytes \
        CONFIG.xdma_rnum_chnl 1 \
        CONFIG.xdma_wnum_chnl 1 \
        CONFIG.xdma_num_usr_irq 4 \
        CONFIG.pf0_msi_enabled true \
        CONFIG.pf0_device_id 9034 \
        CONFIG.cfg_mgmt_if false \
        CONFIG.pipe_sim [expr {$pipe ? "true" : "false"}] \
    ] [get_ips $name]
    return [get_ips $name]
}

# Converters between the PCIe core and the SoC, created next to the XDMA core.
#   pcie_dw   128 -> 64 bit AXI4 downsizer in the PCIe user clock (host DMA master -> 64-bit SoC bus)
#   pcie_cc   64-bit AXI4 asynchronous clock converter, PCIe user clock -> CPU clock (64-bit addresses are kept so axi_win can refuse upper bits)
#   pcie_ccl  AXI4-Lite asynchronous clock converter, PCIe user clock -> peripheral clock (host BAR0 window)
proc make_pcie_converters {} {
    create_ip -name axi_dwidth_converter -vendor xilinx.com -library ip -module_name pcie_dw
    set_property -dict [list CONFIG.ADDR_WIDTH 64 CONFIG.SI_DATA_WIDTH 128 CONFIG.MI_DATA_WIDTH 64 CONFIG.SI_ID_WIDTH 4 CONFIG.PROTOCOL AXI4 \
        CONFIG.ACLK_ASYNC 0] [get_ips pcie_dw]
    create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name pcie_cc
    set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 64 CONFIG.ADDR_WIDTH 64 CONFIG.ID_WIDTH 4 CONFIG.ACLK_ASYNC 1] [get_ips pcie_cc]
    create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name pcie_ccl
    set_property -dict [list CONFIG.PROTOCOL AXI4LITE CONFIG.DATA_WIDTH 32 CONFIG.ADDR_WIDTH 32 CONFIG.ACLK_ASYNC 1] [get_ips pcie_ccl]
}
