#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the bare-metal benchmark ELFs used by fpga/scripts/cpu/sweeps (output: build/bench/*.elf).
# Needs build/tools/xpack-riscv-none-elf-gcc-15.2.0-1 (xPack GCC v15.2.0-1, sha256 aaaa8060...3758) and
# build/third_party/VexiiRiscv with ext/NaxSoftware initialised (CoreMark port, start.S, sim driver headers).
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
tc=$root/build/tools/xpack-riscv-none-elf-gcc-15.2.0-1
ns=$root/build/third_party/VexiiRiscv/ext/NaxSoftware/baremetal
out=$root/build/bench
mkdir -p "$out"
for a in "rv64ima_zicsr_zifencei lp64 rv64ima" "rv32ima_zicsr_zifencei ilp32 rv32ima"; do
	set -- $a
	"$tc/bin/riscv-none-elf-gcc" -O2 -march="$1" -mabi="$2" -mcmodel=medany -DUSE_GP -I"$ns/driver" -nostartfiles \
		-ffreestanding -Wl,-T,"$root/tests/bench/app8m.ld" "$ns/common/start.S" "$root/tests/bench/membench.c" \
		-o "$out/membench_$3.elf" -lgcc
	(cd "$ns/coremark_vexii" && make PORT_DIR=naxriscv_sim RISCV_PATH="$tc" RISCV_NAME=riscv-none-elf MARCH="$1" MABI="$2" \
		ITERATIONS=10 REBUILD=1 XCFLAGS="-DCORE_DEBUG=0" clean compile link >/dev/null && cp coremark_vexii.elf "$out/coremark_$3.elf")
done
git -C "$ns" checkout -q -- . 2>/dev/null || true
