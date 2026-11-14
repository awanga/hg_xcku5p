#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Console input stress: log in, optionally turn echo off, send short commands back to back and count how many
are answered before the console stops. The UART RX interrupt-loss bug (docs/validation/io-expansion.md) showed up as
0, 32 or 51 of 400 with echo off; a healthy board completes all of them.

usage: console_stress.py [--port /dev/ttyUSB2] [--echo] [--count 400]   (the board must be at a login or shell prompt)
Exit status 0 only if every command was answered.
"""

import argparse
import sys
import time

import serial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB2")
    ap.add_argument("--baud", type=int, default=230400)
    ap.add_argument("--echo", action="store_true", help="leave tty echo on (default: stty -echo)")
    ap.add_argument("--count", type=int, default=400)
    a = ap.parse_args()
    s = serial.Serial(a.port, a.baud, timeout=0.2)

    def read_for(t):
        end, b = time.time() + t, b""
        while time.time() < end:
            b += s.read(4096)
        return b

    s.write(b"\n")
    if b"login: " in read_for(2)[-12:]:
        s.write(b"root\n")
        read_for(2)
    if not a.echo:
        s.write(b"stty -echo\n")
        read_for(1)
    done = 0
    for i in range(a.count):
        s.write(("echo B%d\n" % i).encode())
        want = ("B%d\r\n" % i).encode()
        b, end = b"", time.time() + 3
        # With echo on the command itself is echoed back; only the output line counts.
        while time.time() < end and want not in b.replace(("echo B%d\r\n" % i).encode(), b""):
            b += s.read(4096)
        if want not in b.replace(("echo B%d\r\n" % i).encode(), b""):
            break
        done += 1
    print("%s: %d of %d answered" % ("PASS" if done == a.count else "FAIL", done, a.count))
    return 0 if done == a.count else 1


if __name__ == "__main__":
    sys.exit(main())
