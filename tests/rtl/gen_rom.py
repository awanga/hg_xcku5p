#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Write the 64-word test image for tb_soc_periph: word i = ((i * 0x9E3779B1) ^ 0xA5A5A5A5) mod 2**32."""
import sys

with open(sys.argv[1], "w") as f:
    for i in range(64):
        f.write("%08x\n" % (((i * 0x9E3779B1) ^ 0xA5A5A5A5) & 0xFFFFFFFF))
