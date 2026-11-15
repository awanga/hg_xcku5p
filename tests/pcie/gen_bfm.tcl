# SPDX-License-Identifier: MIT
# Generates the vendor root-port test bench files (the XDMA example design's `imports`) for the endpoint configuration in fpga/scripts/pcie/xdma_ip.tcl.
# They are Xilinx's and are not stored in the repository: this script recreates them in <outdir>/exd/xdma_0_ex/imports.
# usage: vivado -mode batch -source gen_bfm.tcl -tclargs <outdir>
set out [file normalize [lindex $argv 0]]
set root [file normalize [file join [file dirname [info script]] .. ..]]
file mkdir $out/ip
create_project -force bfm $out/prj -part xcku5p-ffvb676-2-i
source $root/fpga/scripts/pcie/xdma_ip.tcl
make_xdma xdma_0 $out/ip 1
generate_target all [get_ips xdma_0]
open_example_project -force -dir $out/exd [get_ips xdma_0]
puts "BFM_DONE"
