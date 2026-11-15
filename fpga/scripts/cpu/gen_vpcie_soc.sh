#!/bin/bash
# SPDX-License-Identifier: MIT
# Generate the SoC netlist for the logical PCIe root complex variant (decision 0008): the default SoC (gen_default_soc.sh) plus a 2 MiB
# peripheral region at 0xF9000000 (1 MiB ECAM at +0, 1 MiB BAR window at +0x100000) that reaches the same AXI-Lite peripheral port.
# Output: build/soc/soc_l2u_128k_w4v/soc_l2u_128k_w4v.v
set -eu
here=$(cd "$(dirname "$0")" && pwd)
EXTRA_MEM_ARGS="--memory-region=4177526784,2097152,rw,p" VEXII_L2_BLACKBOX=1 "$here/gen_soc.sh" soc_l2bb_128k_w4v --with-dma --l2-bytes=131072 --l2-ways=4
"$here/uram_l2.sh" soc_l2bb_128k_w4v soc_l2u_128k_w4v
