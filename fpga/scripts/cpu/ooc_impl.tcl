# SPDX-License-Identifier: MIT
# Out-of-context place-and-route of a CPU netlist on the board part, to estimate achievable Fmax.
# vivado -mode batch -source ooc_impl.tcl -tclargs <name> <top> <clk_port> <clk_ns> <io_pct> <outdir> <verilog files...>
# io_pct: input/output delay as a percentage of the period on all other ports (0 = leave ports unconstrained,
# i.e. register-to-register paths only).
lassign [lrange $argv 0 5] name top clkp clk_ns io_pct outdir
set files [lrange $argv 6 end]
set part xcku5p-ffvb676-2-i
file mkdir $outdir
create_project -in_memory -part $part
read_verilog $files
synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk -period $clk_ns [get_ports $clkp]
if {$io_pct > 0} {
    set d [expr {$clk_ns * $io_pct / 100.0}]
    set ins [lsearch -all -inline -not -exact [get_ports -filter {DIRECTION == IN}] [get_ports $clkp]]
    set_input_delay $d -clock clk $ins
    set_output_delay $d -clock clk [get_ports -filter {DIRECTION == OUT}]
}
opt_design
place_design
phys_opt_design
route_design
phys_opt_design
report_utilization -file $outdir/$name.util.rpt
report_timing_summary -file $outdir/$name.timing.rpt
report_clock_utilization -file $outdir/$name.clk.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "OOC_IMPL name=$name clk_ns=$clk_ns io_pct=$io_pct wns=$wns whs=$whs"
