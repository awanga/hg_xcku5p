# SPDX-License-Identifier: MIT
# Root-port simulation of the HG-XCKU5P PCIe endpoint (pcie_ep with its converters, window filter and register block) in xsim, PIPE mode.
# usage: vivado -mode batch -source sim.tcl -tclargs <simdir> <bfm_dir> <testname>
set simdir [file normalize [lindex $argv 0]]
set bfm [file normalize [lindex $argv 1]]
set test [lindex $argv 2]
set root [file normalize [file join [file dirname [info script]] .. ..]]
set imports $bfm/exd/xdma_0_ex/imports
# the vendor files with our test list in place of the vendor tests.vh (which our tests.vh includes the vendor test file from)
file delete -force $simdir/tb
file mkdir $simdir/tb
foreach f [glob $imports/*] { file copy -force $f $simdir/tb/ }
file copy -force $root/tests/pcie/tests.vh $simdir/tb/tests.vh
file mkdir $simdir/ip
create_project -force psim $simdir/prj -part xcku5p-ffvb676-2-i
source $root/fpga/scripts/pcie/xdma_ip.tcl
make_xdma xdma_0 $simdir/ip 1
make_pcie_converters
generate_target all [get_ips]
set rtl {pcie_ep irq_req pcie_regs axi_win axil_simple cdc_cfg}
foreach m $rtl { add_files -norecurse $root/fpga/rtl/$m.v }
# optional mutant: PCIE_WIN_RTL=<file> replaces axi_win.v (a test must fail on it)
if {[info exists ::env(PCIE_WIN_RTL)]} { remove_files $root/fpga/rtl/axi_win.v; add_files -norecurse $::env(PCIE_WIN_RTL) }
add_files -norecurse $root/tests/pcie/xilinx_dma_pcie_ep.v
set bench {}
foreach f {pcie_4_0_rp sys_clk_gen sys_clk_gen_ds usp_pci_exp_usrapp_cfg usp_pci_exp_usrapp_com usp_pci_exp_usrapp_rx usp_pci_exp_usrapp_tx
           xilinx_pcie_uscale_rp xp4_usp_smsw_model_core_top board xil_sig2pipe} {
    if {[file exists $simdir/tb/$f.v]} { lappend bench $simdir/tb/$f.v }
}
add_files -fileset sim_1 -norecurse $bench
foreach h {board_common.vh pci_exp_expect_tasks.vh sample_tests.vh tests.vh} { add_files -fileset sim_1 -norecurse $simdir/tb/$h }
# PCIE_NOCPU=1: the CPU-less build's pcie_ep (BAR0 as a peripheral-bus master port; test pcie_ep_nocpu)
set defs {PCIE_SIM_PIPE}
if {[info exists ::env(PCIE_NOCPU)]} { lappend defs NOCPU }
set_property verilog_define $defs [get_filesets sources_1]
set_property verilog_define $defs [get_filesets sim_1]
set_property include_dirs [list $simdir/tb] [get_filesets sim_1]
set_property top board [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options} -value "-testplusarg TESTNAME=$test" -objects [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
puts "SIM_DONE $test"
