#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""HDMI sink probe over the console (monitor connected, bitstream with the HDMI scan-out): for each OE/ENABLE setting print STATUS (HPD is bit 0)
and look for an EDID header (00 ff ff ff ff ff ff 00) at I2C address 0x50 on both AXI IIC buses. The HDMI1_OUT_EN pin may also gate the connector's
HPD and bridge its DDC lines onto an I2C bus (owner's reading of the schematic), which this checks."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smoke  # noqa: E402

HDMI = 0xF800F000


def main():
    c = smoke.Console("/dev/ttyUSB2", 230400, open(os.devnull, "w"))
    c.s.write(b"\n")
    c.read_until(r"# $", 5)
    c.s.write(b"stty -echo\n")
    c.read_until(r"# $", 3)
    for ctrl in (0, 1, 2, 3):
        out = c.run("devmem 0x%x 32 %d; sleep 1; devmem 0x%x 32" % (HDMI, ctrl, HDMI + 8))[
            0
        ].split()
        print("CTRL=%d STATUS=%s (HPD=%s)" % (ctrl, out[0], int(out[0], 16) & 1))
        for bus in (0, 1):
            hdr = c.run("i2cdump -y -r 0-7 %d 0x50 b 2>&1 | sed -n 2p" % bus, timeout=60)[0]
            print(
                "  bus %d 0x50: %s%s"
                % (bus, hdr[:30], "  <-- EDID" if "00 ff ff ff ff ff ff 00" in hdr else "")
            )
    c.run("devmem 0x%x 32 3" % HDMI)


if __name__ == "__main__":
    main()
