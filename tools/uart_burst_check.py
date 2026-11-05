#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check the console capture of fw/app/uart_burst.c: every line of modes A, B, D must arrive intact and in order.
usage: uart_burst_check.py capture.log"""
import re
import sys

LINES, FILL = 60, 70


def expect(tag, n):
    return "%c%03d " % (tag, n) + "".join(chr(ord("a") + (n + i) % 26) for i in range(FILL))


def main():
    text = open(sys.argv[1], "rb").read().decode("ascii", "replace")
    got = [ln.rstrip("\r") for ln in text.split("\n")]
    bad = 0
    for tag in "ABFD":
        ok = sum(1 for n in range(LINES) if expect(tag, n) in got)
        print("mode %s: %d/%d lines intact" % (tag, ok, LINES))
        bad += LINES - ok
    m = re.search(r"C: ?([A-Za-z]*)", text)
    fa = re.search(r"C full_at=(\d+)", text)
    print("mode C: received %d of 48 chars, TX_FULL first seen after write %s" %
          (len(m.group(1)) if m else -1, fa.group(1) if fa else "?"))
    n_e = sum(1 for ln in got for n in [ln] if re.fullmatch(r"E\d{3} [a-z]{%d}" % FILL, n))
    ok_e = sum(1 for ln in got for n in range(LINES) if ln == expect("E", n))
    print("mode E: %d/%d lines intact (%d E-lines seen)" % (ok_e, 10 * LINES, n_e))
    bad += 10 * LINES - ok_e
    started = "==BURST START" in text and "==BURST END" in text
    print("markers:", "both" if started else "MISSING")
    sys.exit(0 if bad == 0 and started else 1)


main()
