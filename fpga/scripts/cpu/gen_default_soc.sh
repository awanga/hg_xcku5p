#!/bin/bash
# SPDX-License-Identifier: MIT
# Generate the default SoC netlist: VexiiRiscv RV64IMA + coherency hub + 128 KiB 4-way L2 (data banks mapped to UltraRAM).
# Needs the L2 blackbox patch applied to build/third_party/VexiiRiscv (fpga/patches/vexii-l2-blackbox.patch).
# Output: build/soc/soc_l2u_128k_w4/soc_l2u_128k_w4.v (pass the name to build_soc.tcl; "l2" in the name defines WITH_DMA).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
VEXII_L2_BLACKBOX=1 "$here/gen_soc.sh" soc_l2bb_128k_w4 --with-dma --l2-bytes=131072 --l2-ways=4
"$here/uram_l2.sh" soc_l2bb_128k_w4 soc_l2u_128k_w4
