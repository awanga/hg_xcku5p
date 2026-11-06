# SPDX-License-Identifier: MIT
# Close a small setup miss on a routed SoC checkpoint (a few ps to ~0.05 ns): post-route phys_opt, then an Explore re-route, then phys_opt again.
# usage: vivado -mode batch -source fpga/scripts/postroute_fix.tcl -tclargs <in_routed.dcp> <out_prefix>   writes <out_prefix>.dcp, _timing.rpt and, if WNS >= 0, .bit
set in [lindex $argv 0]
set out [lindex $argv 1]
open_checkpoint $in
proc wns {t} { return [get_property SLACK [get_timing_paths -delay_type $t -max_paths 1]] }
phys_opt_design -directive AggressiveExplore
puts "STEP phys_opt wns=[wns max] whs=[wns min]"
if {[wns max] < 0} {
    route_design -directive Explore
    puts "STEP route wns=[wns max] whs=[wns min]"
    foreach d {AggressiveExplore Explore AggressiveFanoutOpt} {
        phys_opt_design -directive $d
        puts "STEP phys_opt $d wns=[wns max] whs=[wns min]"
        if {[wns max] >= 0} break
    }
}
write_checkpoint -force $out.dcp
report_timing_summary -file ${out}_timing.rpt
if {[wns max] >= 0 && [wns min] >= 0} { write_bitstream -force $out.bit } else { puts "NOT MET: no bitstream written" }
