#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Estimate how long a flash-boot configuration takes and compare it with the PCIe budget.

usage: cfg_time.py FILE.bit [--rate MHZ] [--width 4] [--budget-ms 100] [--strict]

A card is enumerated by the host only if it is configured (and its link up) when the host walks the bus. PCI Express CEM allows 100 ms from stable power to
the end of PERST# (Tpvperl) before the card must answer; an FPGA that configures later is missed by a host that scans once at boot and needs a rescan or a
warm reboot. The estimate is size * 8 / (width * rate): the configuration clock only, without the flash's start-up delay or the power-on-reset time, so the
real time is longer. A measured value (DONE vs power good on a scope) replaces it; this tool only shows which side of the budget the image is on.
Exit 0 normally; with --strict, 1 when the estimate exceeds the budget.
"""

import argparse
import os
import sys


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("bit")
    ap.add_argument(
        "--rate", type=float, default=51.0, help="CONFIGRATE in MHz (flash_bit.tcl default 51)"
    )
    ap.add_argument("--width", type=int, default=4, choices=(1, 2, 4, 8))
    ap.add_argument("--budget-ms", type=float, default=100.0)
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()
    size = os.path.getsize(a.bit)
    ms = size * 8 / (a.width * a.rate * 1e6) * 1e3
    print(
        "%s: %.2f MB, %d-bit at %.0f MHz: >= %.0f ms of configuration clock (budget %.0f ms)"
        % (a.bit, size / 1e6, a.width, a.rate, ms, a.budget_ms)
    )
    over = ms > a.budget_ms
    if over:
        need = size * 8 / (a.width * a.budget_ms * 1e-3) / 1e6
        print(
            "OVER BUDGET: needs a configuration clock of >= %.0f MHz to fit (or a smaller image); a host that scans once at boot may miss the card."
            % need
        )
    else:
        print(
            "within budget (estimate; the start-up time before the first flash read is not included)"
        )
    return 1 if (over and a.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
