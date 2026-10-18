#!/bin/bash
# SPDX-License-Identifier: MIT
# Run a bare-metal ELF on a VexiiRiscv configuration in the SpinalSim/Verilator testbench (no RVLS co-simulation).
# usage: bench_vexii.sh <name> <elf> <memory-latency> <Generate options...>; log: build/bench/<name>.log
set -u
build=${BUILD:-$(cd "$(dirname "$0")/../../.." && pwd)/build}
name=$1
elf=$2
lat=$3
shift 3
# Verilator JNI wrapper needs jni.h: use a full JDK (build/tools/jdk-21*) when the system only has a JRE
for j in "$build"/tools/jdk-21*; do [ -d "$j" ] && export JAVA_HOME="$j" PATH="$j/bin:$PATH"; done
mkdir -p "$build/bench"
cd "$build/third_party/VexiiRiscv" || exit 1
"$build/tools/sbt/bin/sbt" "runMain vexiiriscv.tester.TestBench $* --load-elf $elf --no-rvls-check --no-stdin --memory-latency $lat --print-stats --name $name" \
	>"$build/bench/$name.log" 2>&1
echo "EXIT=$?" >>"$build/bench/$name.log"
