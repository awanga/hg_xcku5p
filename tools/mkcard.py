#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build a complete SD card image: boot area (header + OpenSBI + kernel + dtb) followed by an ext4 root partition.

usage: mkcard.py OUT.img --fw fw_jump.bin --kernel Image --dtb x.dtb --rootfs rootfs.ext4 [--data data.ext4]
Layout: sector 0 = boot header (bytes 0..445) + MBR partition table (446..509) + 0x55AA; sectors 1.. = payloads;
partition 1 (Linux, ext4) starts at 16 MiB (sector 32768) and holds rootfs.ext4 (mounted read-only);
partition 2 (Linux, ext4) follows, aligned to 1 MiB, and holds data.ext4 (persistent state, mounted read-write). Load addresses match docs/validation/linux-bringup.md.
This writes a file only. Copying it to a card (dd) overwrites the whole card and is done by the user.
"""
import argparse
import struct
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
import mksd  # noqa: E402

PART_START = 32768  # sectors (16 MiB)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--fw", required=True)
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--dtb", required=True)
    ap.add_argument("--rootfs", required=True)
    ap.add_argument("--data")
    ap.add_argument("--fw-addr", type=lambda x: int(x, 0), default=0x40100000)
    ap.add_argument("--kernel-addr", type=lambda x: int(x, 0), default=0x40200000)
    ap.add_argument("--dtb-addr", type=lambda x: int(x, 0), default=0x41F00000)
    a = ap.parse_args()
    rd = lambda p: open(p, "rb").read()
    boot = mksd.build([(a.fw_addr, rd(a.fw)), (a.kernel_addr, rd(a.kernel)), (a.dtb_addr, rd(a.dtb))], a.fw_addr)
    if len(boot) > PART_START * 512:
        raise SystemExit("boot payload %d bytes exceeds the %d byte boot area" % (len(boot), PART_START * 512))
    rootfs = rd(a.rootfs)
    sectors = (len(rootfs) + 511) // 512
    mbr = bytearray(boot[:512])
    assert not any(mbr[446:512]), "boot header overlaps the partition table"
    mbr[446:462] = struct.pack("<BBBBBBBBII", 0x00, 0xFE, 0xFF, 0xFF, 0x83, 0xFE, 0xFF, 0xFF, PART_START, sectors)
    mbr[510:512] = b"\x55\xAA"
    img = bytes(mbr) + boot[512:]
    img = img.ljust(PART_START * 512, b"\0") + rootfs.ljust(sectors * 512, b"\0")
    if a.data:
        data = rd(a.data)
        dsectors = (len(data) + 511) // 512
        dstart = (PART_START + sectors + 2047) // 2048 * 2048
        mbr[462:478] = struct.pack("<BBBBBBBBII", 0x00, 0xFE, 0xFF, 0xFF, 0x83, 0xFE, 0xFF, 0xFF, dstart, dsectors)
        img = bytes(mbr) + img[512:]
        img = img.ljust(dstart * 512, b"\0") + data.ljust(dsectors * 512, b"\0")
    open(a.out, "wb").write(img)
    print("%s: %d MiB, boot area %d KiB, root partition %d MiB at sector %d%s" % (
        a.out, len(img) >> 20, len(boot) >> 10, sectors >> 11, PART_START,
        ", data partition %d MiB at sector %d" % (dsectors >> 11, dstart) if a.data else ""))


if __name__ == "__main__":
    main()
