#!/bin/bash
# SPDX-License-Identifier: MIT
# Generate a VexiiRiscv netlist with sbt.
# Needs build/third_party/VexiiRiscv (submodules ext/SpinalHDL and ext/rvls initialised) and build/tools/sbt.
# usage: gen_vexii.sh <name> <Generate options...>   output: build/cpu/<name>/VexiiRiscv.v, log build/cpu/<name>.log
set -u
build=${BUILD:-$(cd "$(dirname "$0")/../../.." && pwd)/build}
name=$1
shift
cd "$build/third_party/VexiiRiscv" || exit 1
rm -f VexiiRiscv.v
"$build/tools/sbt/bin/sbt" "runMain vexiiriscv.Generate $*" >"$build/cpu/$name.log" 2>&1
rc=$?
mkdir -p "$build/cpu/$name"
mv VexiiRiscv.v "$build/cpu/$name/" 2>/dev/null
echo "EXIT=$rc" >>"$build/cpu/$name.log"
exit "$rc"
