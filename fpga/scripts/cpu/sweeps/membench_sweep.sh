#!/bin/bash
# SPDX-License-Identifier: MIT
# Reproduces a benchmark sweep (see docs/validation/cpu-benchmarks.md). Run from any directory; needs build/ tools (see build_elfs.sh).
R=$(cd "$(dirname "$0")/../../../.." && pwd)
B64="--xlen=64 --with-mul --with-div --allow-bypass-from=0 --with-lsu-bypass --relaxed-branch --with-rva --with-supervisor --performance-counters=0 --fetch-l1 --lsu-l1 --fetch-l1-mem-data-width-min=64 --lsu-l1-mem-data-width-min=64"
BP="--with-btb --with-ras --with-gshare"
E=$R/build/bench/membench_rv64ima.elf
for lat in 20 40; do
  $R/fpga/scripts/cpu/bench_vexii.sh m64_4k1w_nobp_l$lat $E $lat $B64 --fetch-l1-ways=1 --lsu-l1-ways=1
  $R/fpga/scripts/cpu/bench_vexii.sh m64_8k2w_bp_l$lat   $E $lat $B64 --fetch-l1-ways=2 --lsu-l1-ways=2 $BP
  $R/fpga/scripts/cpu/bench_vexii.sh m64_16k4w_bp_l$lat  $E $lat $B64 --fetch-l1-ways=4 --lsu-l1-ways=4 $BP
  $R/fpga/scripts/cpu/bench_vexii.sh m64_8k2w_bp_sb_l$lat $E $lat $B64 --fetch-l1-ways=2 --lsu-l1-ways=2 --lsu-l1-store-buffer-slots=2 --lsu-l1-store-buffer-ops=32 $BP
  $R/fpga/scripts/cpu/bench_vexii.sh m64_32k4w_bp_l$lat  $E $lat $B64 --fetch-l1-ways=4 --lsu-l1-ways=4 --fetch-l1-sets=128 --lsu-l1-sets=128 $BP
done
echo done
