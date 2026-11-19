#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Board checks for the lean CPU-less PCIe card (build_soc.tcl -card) through the UART2 rig.

usage: card_smoke.py [--port /dev/ttyUSB1] [--reset FILE.bit] [--version X.Y.Z]
--reset loads the bitstream over JTAG first (openFPGALoader --cable ft232); never writes the flash.
Covers: identity words against fpga/pcie_identity.cfg (what the PCIe core in this image enumerates with), the register map, the hook window, the pcie_regs
block, DDR4 through the rig, and the host-side decode of unmapped words. The link itself needs a slot (tools/pcie_identity.py check-lspci on the host).
"""

import argparse
import os
import random
import subprocess
import sys
import time

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import pcie_identity  # noqa: E402
from rig import DDR_BASE, Rig, RigError  # noqa: E402

CARD = 0xF8001000
USER = 0xF8002000
PCIE = 0xF800A000
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
    ap.add_argument("--version", help="expected image version (default: the VERSION file)")
    a = ap.parse_args()
    ver = a.version or open(os.path.join(here, "..", "VERSION")).read().strip()
    vmaj, vmin, vpat = (int(x) for x in ver.split("."))
    ident = pcie_identity.load()
    gen = pcie_identity.generics(ident)
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
        "card_id",
        "ID = CARD, layout 1",
        lambda: (
            (v := (rig.read(CARD), rig.read(CARD + 4))) == (0x43415244, 1),
            [hex(x) for x in v],
        ),
    )
    check(
        "version",
        "VERSION register = %s (a stale image fails here)" % ver,
        lambda: ((v := rig.read(CARD + 8)) == (vmaj << 16 | vmin << 8 | vpat), hex(v)),
    )
    check(
        "build_id",
        "BUILD holds a source commit id (nonzero)",
        lambda: ((v := rig.read(CARD + 0xC)) != 0, hex(v)),
    )
    check(
        "identity",
        "PCI_ID, PCI_CLASS and PCI_SUBSYS equal fpga/pcie_identity.cfg",
        lambda: (
            (v := [rig.read(CARD + o) for o in (0x10, 0x14, 0x18)])
            == [gen["PCI_ID"], gen["PCI_CLASS"], gen["PCI_SUBSYS"]],
            [hex(x) for x in v],
        ),
    )
    check(
        "caps",
        "CAPS = DDR4, PCIe, rig, user window (no board peripherals)",
        lambda: ((v := rig.read(CARD + 0x1C)) == 0xF, hex(v)),
    )
    check(
        "ddr_status",
        "DDR4 calibration complete",
        lambda: ((v := rig.read(CARD + 0x20) & 1) == 1, v),
    )
    check("ddr_size", "DDR_MIB = 1024", lambda: ((v := rig.read(CARD + 0x24)) == 1024, v))

    def uptime():
        t0 = rig.read(CARD + 0x28)
        time.sleep(1.2)
        t1 = rig.read(CARD + 0x28)
        return t1 - t0 in (1, 2), (t0, t1)

    check("uptime", "UPTIME advances about 1 s per second", uptime)

    def scratch():
        for v in (0x5A5AA5A5, 0xFFFFFFFF, 0):
            rig.write(CARD + 0x2C, v)
            if rig.read(CARD + 0x2C) != v:
                return False, hex(v)
        return True, None

    check("scratch", "SCRATCH read-back", scratch)

    def led():
        rig.write(CARD + 0x30, 0xA5)
        v = rig.read(CARD + 0x30)
        rig.write(CARD + 0x30, 0)
        return v == 0xA5, hex(v)

    check("led", "LED register read-back (the LEDs show 0xA5 briefly)", led)
    check(
        "ro_words",
        "writes to ID and PCI_ID are ignored",
        lambda: (
            rig.write(CARD, 0) is None
            and rig.write(CARD + 0x10, 0) is None
            and (rig.read(CARD), rig.read(CARD + 0x10)) == (0x43415244, gen["PCI_ID"]),
            None,
        ),
    )

    def user():
        rig.write(USER + 4, 0x12345678)
        ok = rig.read(USER + 4) == 0x12345678
        rig.write(USER + 4, 0)
        return ok and rig.read(USER + 0x40) == 0 and rig.read(
            USER + 0x8C
        ) == 0x00010000 and rig.read(USER + 0x80) == 0, None

    check("user_regs", "hook window: CTL read-back, STS 0, layout word, KICK reads 0", user)

    def user_events():
        rig.write(USER + 0x88, 0xF)
        rig.write(USER + 0x84, 0xFFFFFFFF)
        return rig.read(USER + 0x84) == 0 and rig.read(USER + 0x88) == 0xF, None

    check("user_events", "event/enable words (no event source connected)", user_events)

    IP = 0xF8004000

    def user_ip():
        for a in (IP, IP + 4, IP + 0x3FFC):
            if rig.read(a) != 0:
                return False, hex(a)
        rig.write(IP, 0xFFFFFFFF)
        rig.write(IP + 0x3FFC, 0x12345678)
        return rig.read(IP) == 0 and rig.read(IP + 0x3FFC) == 0, None

    check(
        "user_ip",
        "user_ip window 0xF8004000..0xF8007FFF reads 0 and ignores writes (no IP attached)",
        user_ip,
    )

    check(
        "pcie_regs",
        "pcie_regs ID 0x50434901 at 0xF800A000 (the host sees it at BAR0 + 0xA000)",
        lambda: ((v := rig.read(PCIE)) == 0x50434901, hex(v)),
    )
    st = []

    def pcie_status():
        st.append(rig.read(PCIE + 4))
        return True, None

    check(
        "pcie_status",
        "STATUS readable (no slot on the bench: link down, PERST# asserted or absent)",
        pcie_status,
    )
    print("INFO pcie STATUS = 0x%X (bit0 link up, bit1 core clock, bit2 PERST# deasserted)" % st[0])

    def mailbox():
        rig.write(PCIE + 0x20, 0xCAFEF00D)
        return rig.read(PCIE + 0x20) == 0xCAFEF00D, None

    check("pcie_mailbox", "mailbox word read-back", mailbox)

    def window():
        rig.write(PCIE + 0x74, 0)
        rig.write(PCIE + 0x70, DDR_BASE)
        rig.write(PCIE + 0x74, 0x100000)
        ok = rig.read(PCIE + 0x70) == DDR_BASE and rig.read(PCIE + 0x74) == 0x100000
        rig.write(PCIE + 0x74, 0)
        return ok and rig.read(PCIE + 0x74) == 0, None

    check(
        "pcie_window", "DMA window registers open and close (the window is closed at reset)", window
    )

    def hole(addr):
        try:
            rig.read(addr)
        except RigError as e:
            if "timeout" in str(e):
                raise
            return rig.read(CARD) == 0x43415244
        return False

    check(
        "decode_error",
        "unmapped words (0xF8003000, 0xF8008000, 0xF800B000) answer a bus error and the bus keeps working",
        lambda: (hole(0xF8003000) and hole(0xF8008000) and hole(0xF800B000), None),
    )

    random.seed(2)
    words = [random.getrandbits(32) for _ in range(64)]

    def ddr_words():
        for i, w in enumerate(words):
            rig.write(DDR_BASE + 4 * i, w)
        bad = [i for i, w in enumerate(words) if rig.read(DDR_BASE + 4 * i) != w]
        return not bad, bad[:8]

    check(
        "ddr_words",
        "64 random words written and read back (all eight lanes of the 256-bit port)",
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

    failed = [n for n, ok in results if not ok]
    print("SMOKE %s (%d of %d failed)" % ("FAIL" if failed else "PASS", len(failed), len(results)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
