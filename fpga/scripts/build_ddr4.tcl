# SPDX-License-Identifier: MIT
# DDR4 bring-up build: vivado -mode batch -source fpga/scripts/build_ddr4.tcl -tclargs <outdir> [tck_ps] [-to synth|impl|bit]
# tck_ps is the DDR4 clock period (default 1250 = DDR4-1600). ui_clk = 4*tck must match UI_CLK_HZ in
# ddr4_bringup_top.v (200 MHz at 1250 ps).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set outdir [file normalize [lindex $argv 0]]
set tck [expr {[llength $argv] > 1 && [string is integer [lindex $argv 1]] ? [lindex $argv 1] : 1250}]
set upto "bit"
set i [lsearch $argv "-to"]
if {$i >= 0} { set upto [lindex $argv [expr {$i + 1}]] }
set part xcku5p-ffvb676-2-i

create_project -force ddr4_bringup $outdir -part $part
create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
set ip [get_ips ddr4_0]
set_property -dict [list \
    CONFIG.C0.DDR4_MemoryPart MT40A256M16GE-075E \
    CONFIG.C0.DDR4_DataWidth 32 \
    CONFIG.C0.DDR4_TimePeriod $tck \
    CONFIG.C0.DDR4_InputClockPeriod 10000 \
    CONFIG.C0.DDR4_AxiSelection true \
    CONFIG.C0.DDR4_DataMask DM_NO_DBI \
    CONFIG.C0.DDR4_EN_PARITY false] $ip
generate_target all $ip

add_files [glob $root/fpga/rtl/*.v]
add_files -fileset constrs_1 [list $root/fpga/constraints/ddr4_pins.xdc $root/fpga/constraints/bringup_board.xdc]
set_property top ddr4_bringup_top [current_fileset]
update_compile_order -fileset sources_1

proc run_to {name step} {
    launch_runs $name -to_step $step -jobs 8
    wait_on_run $name
    set st [get_property STATUS [get_runs $name]]
    puts "RUN $name: $st"
    if {![string match "*Complete*" $st]} { error "$name failed: $st" }
}
run_to synth_1 synth_design
open_run synth_1
report_utilization -file $outdir/synth_utilization.rpt
close_design
if {$upto eq "synth"} { puts "BUILD_DONE synth"; exit 0 }
set_property STEPS.WRITE_BITSTREAM.TCL.PRE {} [get_runs impl_1]
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
puts "RUN impl_1: [get_property STATUS [get_runs impl_1]]"
open_run impl_1
report_utilization -file $outdir/impl_utilization.rpt
report_timing_summary -file $outdir/impl_timing.rpt
report_drc -file $outdir/impl_drc.rpt
report_clock_utilization -file $outdir/impl_clocks.rpt
puts "WNS [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]"
if {$upto eq "bit"} {
    write_bitstream -force $outdir/ddr4_bringup.bit
}
puts "BUILD_DONE $upto"
