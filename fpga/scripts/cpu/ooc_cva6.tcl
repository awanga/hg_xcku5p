# SPDX-License-Identifier: MIT
# Out-of-context synthesis of a CVA6 core configuration on the board part (resource/Fmax estimate only).
# vivado -mode batch -source ooc_cva6.tcl -tclargs <cva6_repo_dir> <TARGET_CFG> <clk_ns> <outdir>
lassign $argv repo cfg clk_ns outdir
set part xcku5p-ffvb676-2-i
file mkdir $outdir
set ::env(CVA6_REPO_DIR) $repo
set ::env(TARGET_CFG) $cfg
set hpd $repo/core/cache_subsystem/hpdcache
set files {}
set incs {}
proc read_flist {path} {
    global repo cfg hpd files incs
    set f [open $path]
    foreach line [split [read $f] "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "//*" $line]} continue
        set line [string map [list \${CVA6_REPO_DIR} $repo \${TARGET_CFG} $cfg \${HPDCACHE_DIR} $hpd] $line]
        if {[string match "-F *" $line]} { read_flist [string trim [string range $line 3 end]]; continue }
        if {[string match "+incdir+*" $line]} { lappend incs [string range $line 8 end]; continue }
        if {[string match "*.sv" $line] || [string match "*.v" $line]} { lappend files $line }
    }
    close $f
}
read_flist $repo/core/Flist.cva6
create_project -in_memory -part $part
read_verilog -sv $files
set_property file_type SystemVerilog [get_files -quiet *.sv]
set t0 [clock seconds]
synth_design -top cva6 -part $part -mode out_of_context -include_dirs $incs -flatten_hierarchy rebuilt
create_clock -name clk -period $clk_ns [get_ports clk_i]
report_utilization -file $outdir/$cfg.util.rpt
report_timing_summary -file $outdir/$cfg.timing.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1]]
puts "OOC_RESULT cfg=$cfg clk_ns=$clk_ns wns=$wns synth_s=[expr {[clock seconds]-$t0}]"
