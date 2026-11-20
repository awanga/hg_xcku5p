#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""PCIe identity of the card (fpga/pcie_identity.cfg): one manifest for the XDMA IP, card_regs and the host-side check.

pcie_identity.py show                    print the manifest
pcie_identity.py generics                print the card_top generics (hex) for Vivado
pcie_identity.py check-ip <ip_dir>       compare the generated PCIe4 core parameters with the manifest (build gate)
pcie_identity.py check-lspci [BDF]       compare `lspci -nn -vv` of the running card with the manifest (host side, after enumeration)
pcie_identity.py check-lspci --text FILE same, from saved lspci output (offline)
"""

import argparse
import mmap
import os
import pathlib
import re
import subprocess
import sys

CFG = pathlib.Path(__file__).resolve().parent.parent / "fpga" / "pcie_identity.cfg"
KEYS = (
    "vendor_id",
    "device_id",
    "subsystem_vendor_id",
    "subsystem_id",
    "class_code",
    "revision_id",
)


def load(path=CFG):
    d = {}
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            k, v = line.split()[:2]
            d[k] = int(v, 16)
    miss = [k for k in KEYS if k not in d]
    if miss:
        raise SystemExit(f"{path}: missing {', '.join(miss)}")
    return d


def generics(d):
    # card_regs words: PCI_ID = {device, vendor}, PCI_CLASS = {class[23:0], revision}, PCI_SUBSYS = {subsystem, subsystem vendor}
    return {
        "PCI_ID": (d["device_id"] << 16) | d["vendor_id"],
        "PCI_CLASS": (d["class_code"] << 8) | d["revision_id"],
        "PCI_SUBSYS": (d["subsystem_id"] << 16) | d["subsystem_vendor_id"],
    }


def check_ip(d, ip_dir):
    files = sorted(pathlib.Path(ip_dir).rglob("*_pcie4_ip.v"))
    files = [f for f in files if f.parent.name == "synth"]
    if not files:
        return [f"no generated *_pcie4_ip.v under {ip_dir}"]
    bad = []
    want = {
        "PF0_VENDOR_ID": (d["vendor_id"], 16),
        "PF0_DEVICE_ID": (d["device_id"], 16),
        "PF0_SUBSYSTEM_VENDOR_ID": (d["subsystem_vendor_id"], 16),
        "PF0_SUBSYSTEM_ID": (d["subsystem_id"], 16),
        "PF0_CLASS_CODE": (d["class_code"], 24),
        "PF0_REVISION_ID": (d["revision_id"], 8),
    }
    for f in files:
        txt = f.read_text()
        for name, (val, bits) in want.items():
            m = re.search(rf"\.{name}\(\d+'[Hh]([0-9A-Fa-f]+)\)", txt)
            if not m:
                bad.append(f"{f.name}: {name} not found")
            elif int(m.group(1), 16) != val:
                bad.append(f"{f.name}: {name} = {m.group(1)}, manifest {val:0{bits // 4}X}")
    return bad


def check_lspci(d, text):
    """`lspci -nn -vv` output of one device (or several: the first with the manifest's vendor:device wins)."""
    bad = []
    vd = f"{d['vendor_id']:04x}:{d['device_id']:04x}"
    blocks = re.split(r"\n(?=\S)", text.strip())
    blk = next((b for b in blocks if f"[{vd}]" in b.split("\n")[0].lower()), None)
    if blk is None:
        return [
            f"no device {vd} in the lspci output (the card did not enumerate with the manifest IDs)"
        ]
    head = blk.split("\n")[0].lower()
    cls = re.search(r"\[([0-9a-f]{4})\]: ", head)
    if cls and int(cls.group(1), 16) != d["class_code"] >> 8:
        bad.append(f"class {cls.group(1)} (manifest {d['class_code'] >> 8:04x})")
    elif not cls:
        bad.append("class not printed (use lspci -nn)")
    rev = re.search(r"\(rev ([0-9a-f]{2})\)", head)
    if (int(rev.group(1), 16) if rev else 0) != d["revision_id"]:
        bad.append(f"revision {rev.group(1) if rev else '00'} (manifest {d['revision_id']:02x})")
    ss = re.search(r"subsystem: .*\[([0-9a-f]{4}):([0-9a-f]{4})\]", blk.lower())
    if not ss:
        bad.append("subsystem IDs not found (run lspci -nn -vv)")
    elif (int(ss.group(1), 16), int(ss.group(2), 16)) != (
        d["subsystem_vendor_id"],
        d["subsystem_id"],
    ):
        bad.append(
            f"subsystem {ss.group(1)}:{ss.group(2)} (manifest {d['subsystem_vendor_id']:04x}:{d['subsystem_id']:04x})"
        )
    return bad


CARD_REGS_OFF = 0x1000  # card_regs in BAR0 (fpga/rtl/card_regs.v)


def host_check(d, bdf, sysfs="/sys/bus/pci/devices"):
    """Config-space IDs as the kernel enumerated them (sysfs), and the identity words the fabric reports through BAR0."""
    base = pathlib.Path(sysfs) / bdf
    if not base.is_dir():
        return [
            f"{base} does not exist (the card is not enumerated at {bdf}; if the host booted before the FPGA finished configuring, rescan with: echo 1 | sudo tee /sys/bus/pci/rescan)"
        ]

    def rd(name):
        return int((base / name).read_text().strip(), 16)

    bad = []
    got = {
        "vendor": (rd("vendor"), d["vendor_id"]),
        "device": (rd("device"), d["device_id"]),
        "subsystem vendor": (rd("subsystem_vendor"), d["subsystem_vendor_id"]),
        "subsystem": (rd("subsystem_device"), d["subsystem_id"]),
        "class": (rd("class"), d["class_code"]),
    }
    for k, (have, want) in got.items():
        if have != want:
            bad.append(f"{k} {have:x} (manifest {want:x})")
    g = generics(d)
    try:
        fd = os.open(base / "resource0", os.O_RDONLY)
    except OSError as e:
        return bad + [f"resource0: {e}"]
    try:
        m = mmap.mmap(fd, 0x2000, prot=mmap.PROT_READ)
        words = [
            int.from_bytes(m[CARD_REGS_OFF + o : CARD_REGS_OFF + o + 4], "little")
            for o in (0x00, 0x10, 0x14, 0x18)
        ]
        m.close()
    except (OSError, ValueError) as e:
        return bad + [f"BAR0 read: {e}"]
    finally:
        os.close(fd)
    if words[0] != 0x43415244:
        bad.append(
            f"card_regs ID {words[0]:08x} at BAR0+0x1000 (not a card image, or memory decoding is off)"
        )
    else:
        for name, w, want in (
            ("PCI_ID", words[1], g["PCI_ID"]),
            ("PCI_CLASS", words[2], g["PCI_CLASS"]),
            ("PCI_SUBSYS", words[3], g["PCI_SUBSYS"]),
        ):
            if w != want:
                bad.append(
                    f"image {name} {w:08x} (manifest {want:08x}): the bitstream was built from another identity"
                )
    return bad


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("cmd", choices=["show", "generics", "check-ip", "check-lspci", "host-check"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument(
        "--text", help="check-lspci: saved lspci -nn -vv output instead of running lspci"
    )
    ap.add_argument("--cfg", default=str(CFG))
    ap.add_argument(
        "--sysfs",
        default="/sys/bus/pci/devices",
        help="host-check: sysfs device directory (for tests)",
    )
    a = ap.parse_args()
    d = load(a.cfg)
    if a.cmd == "show":
        for k in KEYS:
            print(
                f"{k} {d[k]:0{4 if k != 'class_code' and k != 'revision_id' else (6 if k == 'class_code' else 2)}X}"
            )
        return 0
    if a.cmd == "generics":
        print(" ".join(f"{k}=32'h{v:08X}" for k, v in generics(d).items()))
        return 0
    if a.cmd == "check-ip":
        if not a.arg:
            ap.error("check-ip needs the IP directory")
        bad = check_ip(d, a.arg)
    elif a.cmd == "host-check":
        if not a.arg:
            ap.error("host-check needs the device address, e.g. 0000:01:00.0")
        bad = host_check(d, a.arg, a.sysfs)
    else:
        if a.text:
            text = pathlib.Path(a.text).read_text()
        else:
            cmd = ["lspci", "-nn", "-vv"] + (
                ["-s", a.arg] if a.arg else ["-d", f"{d['vendor_id']:04x}:{d['device_id']:04x}"]
            )
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode != 0:
                raise SystemExit(f"{' '.join(cmd)}: {r.stderr.strip()}")
            text = r.stdout
        bad = check_lspci(d, text)
    for b in bad:
        print("FAIL", b)
    print("identity", "FAIL" if bad else "OK")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
