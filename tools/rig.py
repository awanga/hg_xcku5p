#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Client for the UART test rig of the CPU-less variant (fpga/rtl/uart_rig.v, UART2 = /dev/ttyUSB1 at 230400 8N1).

  rig.py [-p PORT] V | I | R ADDR | W ADDR DATA | B ADDR COUNT

Library: Rig(port).read(addr), .write(addr, data), .burst(addr, n), .irq(), .ident(). A bus error on the card raises RigError.
Addresses 0x40000000-0x7FFFFFFF are DDR4, everything else is the peripheral bus (docs/validation/soc-minimal.md, tests/dts/xbar_map.csv).
"""

import argparse
import sys
import time

import serial

DDR_BASE = 0x40000000


class RigError(Exception):
    pass


class Rig:
    def __init__(self, port="/dev/ttyUSB1", baud=230400, timeout=2.0):
        self.s = serial.Serial(port, baud, timeout=timeout)
        self.s.reset_input_buffer()

    def _line(self):
        data = self.s.readline()
        if not data.endswith(b"\n"):
            raise RigError("no reply from the rig (timeout)")
        return data.decode("ascii", "replace").strip()

    def _cmd(self, text):
        self.s.write(text.encode("ascii") + b"\n")
        return self._line()

    def sync(self):
        """Discard stale bytes and check the rig answers (a command interrupted mid-line leaves a malformed line behind)."""
        self.s.write(b"\n")
        time.sleep(0.05)
        self.s.reset_input_buffer()
        return self.ident()

    def ident(self):
        r = self._cmd("V")
        if r != "HGRIG1":
            raise RigError("unexpected identification %r" % r)
        return r

    def irq(self):
        return int(self._cmd("I"), 16)

    def read(self, addr):
        r = self._cmd("R %08X" % addr)
        if r == "ERR":
            raise RigError("bus error reading 0x%08X" % addr)
        return int(r, 16)

    def write(self, addr, data):
        r = self._cmd("W %08X %08X" % (addr, data & 0xFFFFFFFF))
        if r != "OK":
            raise RigError("bus error writing 0x%08X (%s)" % (addr, r))

    def burst(self, addr, n):
        self.s.write(("B %08X %X\n" % (addr, n)).encode("ascii"))
        out = []
        for i in range(n):
            r = self._line()
            if r == "ERR":
                raise RigError("bus error in burst at 0x%08X" % (addr + 4 * i))
            out.append(int(r, 16))
        return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1")
    ap.add_argument("cmd", choices=["V", "I", "R", "W", "B"])
    ap.add_argument("args", nargs="*")
    a = ap.parse_args()
    try:
        r = Rig(a.port)
        r.sync()
        n = {"V": 0, "I": 0, "R": 1, "W": 2, "B": 2}[a.cmd]
        if len(a.args) != n:
            ap.error("%s takes %d argument(s)" % (a.cmd, n))
        v = [int(x, 16) for x in a.args]
        if a.cmd == "V":
            print(r.ident())
        elif a.cmd == "I":
            print("%08X" % r.irq())
        elif a.cmd == "R":
            print("%08X" % r.read(v[0]))
        elif a.cmd == "W":
            r.write(v[0], v[1])
            print("OK")
        else:
            for i, w in enumerate(r.burst(v[0], v[1])):
                print("%08X: %08X" % (v[0] + 4 * i, w))
    except (RigError, serial.SerialException) as e:
        print("rig: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
