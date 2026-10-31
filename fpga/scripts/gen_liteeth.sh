#!/bin/bash
# SPDX-License-Identifier: MIT
# Generate the LiteEth core (Verilog) from fpga/ip/liteeth/*.yml with the LiteX/LiteEth pinned in docs/versions.md.
# One-time setup: python3 -m venv build/tools/litex-venv; clone enjoy-digital/litex and enjoy-digital/liteeth to build/third_party/
# (litex_up, liteeth_up), check out the pinned commits, then `build/tools/litex-venv/bin/pip install --no-deps` both.
# usage: fpga/scripts/gen_liteeth.sh [config.yml] [absolute-outdir]   (default: liteeth_gmii.yml -> build/liteeth)
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
cfg=${1:-$here/fpga/ip/liteeth/liteeth_gmii.yml}
out=${2:-$here/build/liteeth}
mkdir -p "$out"
cd "$out"
"$here/build/tools/litex-venv/bin/liteeth_gen" "$cfg" --output-dir "$out"

# LiteEthPHYGMII forwards the PHY's RX clock to GTX_CLK and clocks its TX domain from it, but the RTL8211EG only provides a 125 MHz
# RXCLK once a link is up and expects 125 MHz on GTX_CLK in 1000BASE-T mode. Clock the TX domain (and so GTX_CLK) from the
# gmii_clocks_tx input instead, which the SoC drives with a 125 MHz clock generated in the FPGA.
# MDC/MDIO have no FPGA pin on this board (docs/hardware/board-inventory.md), but the generated core wraps MDIO in an IOBUF that
# the placer cannot leave unplaced. Replace it with an idle input (MDIO reads as 1); the gmii_mdio port stays, unconnected.
python3 - "$out/gateware/liteeth_core.v" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
pat = re.compile(r"IOBUF IOBUF\(.*?\n\);\n", re.S)
assert len(pat.findall(s)) == 1, "expected exactly one IOBUF instance"
s = pat.sub("assign maccore_ethphy_data_r = 1'b1;\n", s)
tx = "maccore_ethphy_eth_tx_clk = gmii_clocks_rx;"
assert s.count(tx) == 1, "expected exactly one TX clock mux"
s = s.replace(tx, "maccore_ethphy_eth_tx_clk = gmii_clocks_tx;")
open(p, "w").write(s)
PY
