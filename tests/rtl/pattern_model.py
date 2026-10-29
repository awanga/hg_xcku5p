# SPDX-License-Identifier: MIT
"""Independent model of the axi_memtest pattern; prints the vectors hard-coded in tb_axi_memtest.v."""
M = 0xFFFFFFFF


def word(beat, lane, p):
    key = (p * 0x9E3779B9 + 0xA5A5A5A5) & M
    x = ((beat * 8 + lane + 1) & M) ^ key
    x ^= (x << 13) & M
    x ^= x >> 17
    x ^= (x << 5) & M
    return x


for beat, lane, p in [(0, 0, 0), (0, 7, 0), (1, 0, 0), (15, 3, 0), (0, 0, 1), (100, 5, 1), (100, 5, 2)]:
    print("beat %d lane %d pass %d 32'h%08x" % (beat, lane, p, word(beat, lane, p)))
