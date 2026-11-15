#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check that the crossbar ranges in fpga/scripts/build_soc.tcl equal tests/dts/xbar_map.csv, that windows do not overlap and that each base is
aligned to its size. usage: xbar_map.py [tcl] [csv]; exit 1 on any mismatch."""

import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
tcl = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "../../fpga/scripts/build_soc.tcl")
csv = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "xbar_map.csv")

want = {}
for line in open(csv):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    m, base, width, rng = line.split(",")
    want[(int(m), int(rng))] = (int(base, 16), int(width))

text = open(tcl).read()
# only the peripheral crossbar (xbar_per) is described by the table; xbar_dma (the shared DMA port) has one range covering all memory
start = text.index("module_name xbar_per")
text = text[start : text.index("create_ip", start + 1)]
base = {
    (int(m), int(r)): int(v, 16)
    for m, r, v in re.findall(r"CONFIG\.M(\d+)_A(\d+)_BASE_ADDR\s+0x([0-9A-Fa-f]+)", text)
}
width = {
    (int(m), int(r)): int(v)
    for m, r, v in re.findall(r"CONFIG\.M(\d+)_A(\d+)_ADDR_WIDTH\s+(\d+)", text)
}
got = {k: (base[k], width.get(k)) for k in base}
errors = 0
if got != want:
    errors += 1
    for k in sorted(set(got) | set(want)):
        if got.get(k) != want.get(k):
            print(
                "MISMATCH master %d range %d: tcl %s, expected %s"
                % (k[0], k[1], got.get(k), want.get(k))
            )
spans = sorted((b, b + (1 << w), k) for k, (b, w) in want.items())
for (_b0, e0, k0), (b1, _e1, k1) in zip(spans, spans[1:]):
    if b1 < e0:
        errors += 1
        print("OVERLAP %s and %s" % (k0, k1))
for k, (b, w) in want.items():
    if b % (1 << w):
        errors += 1
        print("UNALIGNED %s" % (k,))
print("xbar_map ranges=%d errors=%d %s" % (len(want), errors, "PASS" if not errors else "FAIL"))
sys.exit(1 if errors else 0)
