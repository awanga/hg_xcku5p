#!/bin/bash
# SPDX-License-Identifier: MIT
# Generate a VexiiRiscv SoC netlist (CPU + TileLink fabric + optional coherent L2 + AXI4 memory / AXI-Lite peripheral ports).
# usage: gen_soc.sh <name> [extra SocGen options...]   output: build/soc/<name>/<name>.v, log build/soc/<name>.log
set -u
build=${BUILD:-$(cd "$(dirname "$0")/../../.." && pwd)/build}
name=$1
shift
cpu_args="--xlen=64 --with-mul --with-div --allow-bypass-from=0 --with-lsu-bypass --relaxed-branch --with-rva
 --with-supervisor --with-user --performance-counters=0 --fetch-l1 --lsu-l1 --fetch-l1-mem-data-width-min=64
 --lsu-l1-mem-data-width-min=64 --fetch-l1-ways=4 --lsu-l1-ways=4 --with-btb --with-ras --with-gshare
 --fetch-l1-hardware-prefetch=nl --fetch-l1-refill-count=2 --lsu-hardware-prefetch=rpt --lsu-l1-refill-count=2"
mem_args="--memory-region=1073741824,1073741824,rwxc,m --memory-region=268435456,65536,rwxc,p
 --memory-region=4160749568,65536,rw,p --litedram-width=256 --reset-vector=268435456"
mkdir -p "$build/soc/$name"
cd "$build/third_party/VexiiRiscv" || exit 1
"$build/tools/sbt/bin/sbt" "runMain vexiiriscv.soc.litex.SocGen $(echo $cpu_args $mem_args) $* --netlist-directory $build/soc/$name --netlist-name $name" >"$build/soc/$name.log" 2>&1
rc=$?
echo "EXIT=$rc" >>"$build/soc/$name.log"
exit "$rc"
