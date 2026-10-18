# SPDX-License-Identifier: MIT
# Fails unless Vivado can run the full flow (synth -> bitstream) for the board part.
set part xcku5p-ffvb676-2-i
create_project -in_memory -part $part
puts "VIVADO_VERSION [version -short]"
puts "PART_FOUND [llength [get_parts $part]]"
set d [file normalize [file join [pwd] check_vivado_tmp]]
file mkdir $d
set f [open $d/t.v w]
puts $f "module t(input clk, input d, output reg q); always @(posedge clk) q <= ~d; endmodule"
close $f
set f [open $d/t.xdc w]
puts $f "set_property PACKAGE_PIN T24 \[get_ports clk\]\nset_property IOSTANDARD LVCMOS12 \[get_ports clk\]"
puts $f "set_property PACKAGE_PIN N19 \[get_ports d\]\nset_property IOSTANDARD LVCMOS12 \[get_ports d\]"
puts $f "set_property PACKAGE_PIN E16 \[get_ports q\]\nset_property IOSTANDARD LVCMOS18 \[get_ports q\]"
close $f
read_verilog $d/t.v
read_xdc $d/t.xdc
synth_design -top t -part $part
opt_design
place_design
route_design
write_bitstream -force $d/t.bit
puts "CHECK_VIVADO_PASS"
