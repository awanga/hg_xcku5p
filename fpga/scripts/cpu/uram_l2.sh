#!/bin/bash
# SPDX-License-Identifier: MIT
# Map the L2 data banks of a netlist generated with VEXII_L2_BLACKBOX=1 (see fpga/patches/vexii-l2-blackbox.patch) to UltraRAM.
# usage: uram_l2.sh <in_name> <out_name>   -> build/soc/<out_name>/<out_name>.v (module renamed)
set -eu
build=${BUILD:-$(cd "$(dirname "$0")/../../.." && pwd)/build}
mkdir -p "$build/soc/$2"
perl -0pe 's/Ram_1w_1rs(\s*#\((?:(?!\)\s*\w+\s*\().)*?\)\s*cache_data_banks_)/Ram_1w_1rs_ultra$1/gs; s/module '"$1"'\b/module '"$2"'/' \
	"$build/soc/$1/$1.v" >"$build/soc/$2/$2.v"
echo "ultra instances: $(grep -c 'Ram_1w_1rs_ultra' "$build/soc/$2/$2.v")"
