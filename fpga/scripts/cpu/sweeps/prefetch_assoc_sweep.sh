#!/bin/bash
# SPDX-License-Identifier: MIT
# Reproduces a benchmark sweep (see docs/validation/cpu-benchmarks.md). Run from any directory; needs build/ tools (see build_elfs.sh).
R=$(cd "$(dirname "$0")/../../../.." && pwd)
B64="--xlen=64 --with-mul --with-div --allow-bypass-from=0 --with-lsu-bypass --relaxed-branch --with-rva --with-supervisor --performance-counters=0 --fetch-l1 --lsu-l1 --fetch-l1-mem-data-width-min=64 --lsu-l1-mem-data-width-min=64"
BP="--with-btb --with-ras --with-gshare"
PF="--fetch-l1-hardware-prefetch=nl --fetch-l1-refill-count=2 --lsu-hardware-prefetch=rpt --lsu-l1-refill-count=2"
E=$R/build/bench/membench_rv64ima.elf; C=$R/build/bench/coremark_rv64ima.elf
for lat in 20 40; do
  $R/fpga/scripts/cpu/bench_vexii.sh m64_8k2w_bp_pf_l$lat  $E $lat $B64 --fetch-l1-ways=2 --lsu-l1-ways=2 $BP $PF
  $R/fpga/scripts/cpu/bench_vexii.sh m64_16k4w_bp_pf_l$lat $E $lat $B64 --fetch-l1-ways=4 --lsu-l1-ways=4 $BP $PF
  $R/fpga/scripts/cpu/bench_vexii.sh m64_32k8w_bp_l$lat    $E $lat $B64 --fetch-l1-ways=8 --lsu-l1-ways=8 $BP
done
$R/fpga/scripts/cpu/bench_vexii.sh r64_8k2w_bp_pf_l20  $C 20 $B64 --fetch-l1-ways=2 --lsu-l1-ways=2 $BP $PF
$R/fpga/scripts/cpu/bench_vexii.sh r64_32k8w_bp_l20    $C 20 $B64 --fetch-l1-ways=8 --lsu-l1-ways=8 $BP
# resource variants
gen() { n=$1; shift; $R/fpga/scripts/cpu/gen_vexii.sh $n $B64 "$@" || return
  vivado -mode batch -nojournal -log $R/build/cpu/$n/ooc.log -source $R/fpga/scripts/cpu/ooc_verilog.tcl -tclargs $n VexiiRiscv clk 8.0 $R/build/cpu/$n $R/build/cpu/$n/VexiiRiscv.v > $R/build/cpu/$n/ooc.out 2>&1; }
source ~/.profile; source /opt/Xilinx/2026.1/Vivado/settings64.sh
gen v64_8k2w_pf  --fetch-l1-ways=2 --lsu-l1-ways=2 $BP $PF
gen v64_16k4w_pf --fetch-l1-ways=4 --lsu-l1-ways=4 $BP $PF
gen v64_32k8w    --fetch-l1-ways=8 --lsu-l1-ways=8 $BP
echo done
