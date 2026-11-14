# SPDX-License-Identifier: MIT
# Out-of-context synthesis of a generated CPU netlist on the board part (resource/Fmax estimate only).
# vivado -mode batch -source ooc_verilog.tcl -tclargs <name> <top> <clk_port> <clk_ns> <outdir> <verilog files...>
set name [lindex $argv 0]
set top [lindex $argv 1]
set clkp [lindex $argv 2]
set clk_ns [lindex $argv 3]
set outdir [lindex $argv 4]
set files [lrange $argv 5 end]
set part xcku5p-ffvb676-2-i
file mkdir $outdir
create_project -in_memory -part $part
read_verilog $files
set t0 [clock seconds]
synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk -period $clk_ns [get_ports $clkp]
report_utilization -file $outdir/$name.util.rpt
report_timing_summary -file $outdir/$name.timing.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1]]
puts "OOC_RESULT cfg=$name clk_ns=$clk_ns wns=$wns synth_s=[expr {[clock seconds]-$t0}]"
