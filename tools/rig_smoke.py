#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Board checks for the CPU-less build (decision 0008, variant 3) through the UART2 test rig: peripheral registers, DDR4, the hub DMA port.

usage: rig_smoke.py [--port /dev/ttyUSB1] [--reset FILE.bit] [--log DIR]
--reset loads the bitstream over JTAG first (openFPGALoader --cable ft232). The card has no CPU, so nothing else needs to boot.
"""

import argparse
import os
import random
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rig import DDR_BASE, Rig, RigError  # noqa: E402

REGS = 0xF8001000  # board registers (fpga/rtl/soc_regs.v)
EDMA = 0xF800E000  # eth_dma copy engine
HDMI = 0xF800F000  # HDMI scan-out
ROM = 0x10000000  # boot ROM window (all zero in this build)

results = []


def check(name, desc, fn):
    try:
        ok, got = fn()
    except RigError as e:
        ok, got = False, "rig: %s" % e
    results.append((name, ok))
    print(
        "%s %s: %s%s"
        % ("PASS" if ok else "FAIL", name, desc, "" if ok else "  [got: %r]" % (got,)),
        flush=True,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--reset")
    ap.add_argument("--log", default="build/smoke")
    a = ap.parse_args()
    if a.reset:
        r = subprocess.run(
            ["openFPGALoader", "--cable", "ft232", a.reset], capture_output=True, text=True
        )
        if r.returncode:
            print("FAIL load: %s" % r.stderr[-300:])
            return 1
        time.sleep(3)  # DDR4 calibration
    rig = Rig(a.port)

    check("rig_ident", "the rig answers V with HGRIG1", lambda: (rig.sync() == "HGRIG1", None))
    check(
        "ddr_status",
        "DDR4 calibrated, ui_clk reset released (board regs STATUS = 3)",
        lambda: ((v := rig.read(REGS + 8)) == 3, hex(v)),
    )
    check("cpu_clk", "CPU_KHZ register 333333", lambda: ((v := rig.read(REGS + 0xC)) == 333333, v))
    check(
        "scratch",
        "scratch register read-back",
        lambda: (
            rig.write(REGS + 0x14, 0x5A5AA5A5) is None and rig.read(REGS + 0x14) == 0x5A5AA5A5,
            None,
        ),
    )

    def led():
        rig.write(REGS, 0xA5)
        v = rig.read(REGS)
        rig.write(REGS, 0)
        return v == 0xA5, hex(v)

    check("led_reg", "LED register read-back (the LEDs show 0xA5 briefly)", led)
    check(
        "die_temp",
        "SYSMON temperature code present",
        lambda: ((v := rig.read(REGS + 0x20) & 0xFFFF) != 0, hex(v)),
    )
    check(
        "irq_vector",
        "I returns the interrupt vector",
        lambda: (0 <= (v := rig.irq()) < 2**32, hex(v)),
    )
    check(
        "decode_error",
        "an unmapped peripheral address answers a bus error and the bus keeps working",
        lambda: (_decode_err(rig), None),
    )

    random.seed(1)
    words = [random.getrandbits(32) for _ in range(64)]

    def ddr_words():
        for i, w in enumerate(words):
            rig.write(DDR_BASE + 4 * i, w)
        bad = [i for i, w in enumerate(words) if rig.read(DDR_BASE + 4 * i) != w]
        return not bad, bad[:8]

    check(
        "ddr_words",
        "64 random words written and read back one by one (all eight 32-bit lanes of the 256-bit port)",
        ddr_words,
    )
    check(
        "ddr_burst",
        "B reads the same 64 words back",
        lambda: ((v := rig.burst(DDR_BASE, 64)) == words, [hex(x) for x in v[:4]]),
    )

    def ddr_far():
        addrs = [DDR_BASE + 0x00100000, DDR_BASE + 0x10000000, DDR_BASE + 0x3FFFFFFC]
        for i, ad in enumerate(addrs):
            rig.write(ad, 0xC0DE0000 + i)
        got = [rig.read(ad) for ad in addrs]
        return got == [0xC0DE0000 + i for i in range(3)], [hex(x) for x in got]

    check("ddr_far", "words at +1 MiB, +256 MiB and the last word of the 1 GiB window", ddr_far)

    def edma_write():
        # eth_dma copies from the peripheral bus to DDR through the hub DMA port (64-bit single beats, upsized to the 256-bit port)
        rig.write(REGS + 0x14, 0x11223344)
        dst = DDR_BASE + 0x00200103  # unaligned destination
        for o in range(0, 16, 4):
            rig.write(DDR_BASE + 0x00200100 + o, 0)
        rig.write(EDMA + 0x00, REGS + 0x14)
        rig.write(EDMA + 0x04, dst)
        rig.write(EDMA + 0x08, 4)
        rig.write(EDMA + 0x0C, 1)
        for _ in range(100):
            st = rig.read(EDMA + 0x0C)
            if st & 2:
                break
        got = [rig.read(DDR_BASE + 0x00200100 + o) for o in range(0, 12, 4)]
        rig.write(EDMA + 0x0C, 6)
        # little-endian bytes 44 33 22 11 land at 0x103..0x106
        return (st & 6) == 2 and got == [0x44000000, 0x00112233, 0], (
            hex(st),
            [hex(x) for x in got],
        )

    check(
        "hub_dma_write",
        "eth_dma copies 4 bytes from the board registers to an unaligned DDR4 address (hub DMA write path)",
        edma_write,
    )

    def hdmi_read():
        rig.write(HDMI + 4, DDR_BASE + 0x00400000)
        rig.write(HDMI + 8, 0x1C)  # clear sticky flags and counters
        rig.write(HDMI, 1)  # scan-out on, connector switch off
        time.sleep(0.2)
        st = rig.read(HDMI + 8)
        frames = rig.read(HDMI + 0xC)
        lines = rig.read(HDMI + 0x14)
        late = rig.read(HDMI + 0x10)
        rig.write(HDMI, 0)
        return (st & 0x2) and not (st & 0x8) and frames >= 5 and lines >= 5 * 768 and late == 0, (
            hex(st),
            frames,
            lines,
            late,
        )

    check(
        "hub_dma_read",
        "the HDMI scan-out runs 0.2 s reading the frame buffer from DDR4 without late lines or read errors (hub DMA read path)",
        hdmi_read,
    )

    failed = [n for n, ok in results if not ok]
    print("SMOKE %s (%d failed)" % ("FAIL" if failed else "PASS", len(failed)))
    os.makedirs(a.log, exist_ok=True)
    return 1 if failed else 0


def _decode_err(rig):
    try:
        rig.read(0x20000000)
    except RigError as e:
        if "timeout" in str(e):
            raise
        rig.read(REGS + 8)
        return True
    return False


if __name__ == "__main__":
    sys.exit(main())
