#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the raw SD boot image read by fw/boot (sector 0 header, then payloads at 512-byte sectors).

usage: mksd.py OUT.img [--entry ADDR] file@addr [file@addr ...]      (--hex writes one hex byte per line for the simulation)
Header (little endian): "HGXBOOT\\0", entry count, entry address, then {lba, bytes, load address} per entry (max 8).
Writing the image to a card is a separate, destructive step (dd); this tool only creates the file.
"""
import argparse
import struct

MAGIC = b"HGXBOOT\0"
MAX = 8


def build(entries, entry):
    if not 0 < len(entries) <= MAX:
        raise SystemExit("need 1..%d images" % MAX)
    lba = 1
    table, payload = [], b""
    for addr, data in entries:
        table.append((lba, len(data), addr))
        pad = -len(data) % 512
        payload += data + bytes(pad)
        lba += (len(data) + pad) // 512
    hdr = MAGIC + struct.pack("<II", len(entries), entry)
    for t in table:
        hdr += struct.pack("<III", *t)
    return hdr.ljust(512, b"\0") + payload


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--entry", type=lambda x: int(x, 0), default=None)
    ap.add_argument("--hex", action="store_true")
    a = ap.parse_args()
    entries = []
    for spec in a.images:
        path, _, at = spec.partition("@")
        entries.append((int(at, 0), open(path, "rb").read()))
    entry = a.entry if a.entry is not None else entries[0][0]
    img = build(entries, entry)
    if a.hex:
        open(a.out, "w").write("".join("%02x\n" % b for b in img))
    else:
        open(a.out, "wb").write(img)
    print("%s: %d bytes, %d images, entry 0x%x" % (a.out, len(img), len(entries), entry))


if __name__ == "__main__":
    main()
