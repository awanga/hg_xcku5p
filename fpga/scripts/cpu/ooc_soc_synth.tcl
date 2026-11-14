# SPDX-License-Identifier: MIT
# Out-of-context synthesis-only utilization of a SoC netlist.
# vivado -mode batch -source ooc_soc_synth.tcl -tclargs <name> <outdir> <verilog files...>
lassign [lrange $argv 0 1] name outdir
set files [lrange $argv 2 end]
set part xcku5p-ffvb676-2-i
file mkdir $outdir
create_project -in_memory -part $part
read_verilog $files
synth_design -top $name -part $part -mode out_of_context -flatten_hierarchy rebuilt
report_utilization -file $outdir/$name.synth_util.rpt
puts "OOC_SYNTH name=$name done"
