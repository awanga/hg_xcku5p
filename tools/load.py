#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Load a raw binary into DDR4 through the boot ROM loader and optionally run it.

usage: load.py [-p PORT] [-b BAUD] [-a ADDR] [--run ADDR] [--no-run] image.bin[@ADDR] [image2.bin@ADDR ...]
       load.py --make-stream image.bin OUT [-a ADDR]     (byte stream for the simulation testbench)
Images without @ADDR go to -a (default 0x40100000). The program starts at --run (default: the first image's address).
"""
import argparse
import sys
import time


def stream(image, addr):
    return b"W %x %x\n" % (addr, len(image)) + image + b"G %x\n" % addr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", nargs="+", help="file[@addr]; with --make-stream: image OUT")
    ap.add_argument("--run", type=lambda x: int(x, 0), default=None)
    ap.add_argument("-p", "--port", default="/dev/ttyUSB2")
    ap.add_argument("-b", "--baud", type=int, default=230400)
    ap.add_argument("-a", "--addr", type=lambda x: int(x, 0), default=0x40100000)
    ap.add_argument("--no-run", action="store_true")
    ap.add_argument("--make-stream", action="store_true")
    ap.add_argument("--listen", type=float, default=5.0, help="seconds of console output to show after GO")
    a = ap.parse_args()
    if a.make_stream:
        image = open(a.image[0], "rb").read()
        data = stream(image, a.addr)
        with open(a.image[1], "w") as f:
            f.write("".join("%02x\n" % b for b in data))
        return 0

    import serial

    s = serial.Serial(a.port, a.baud, timeout=2)
    s.reset_input_buffer()
    s.write(b"\n")  # wake the loader; an unknown command is ignored
    deadline = time.time() + 20
    buf = b""
    while not buf.endswith(b"> ") and time.time() < deadline:
        buf += s.read(64)
    if not buf.endswith(b"> "):
        print("no loader prompt; console said: %r" % buf[-200:], file=sys.stderr)
        return 1
    images = []
    for spec in a.image:
        path, _, at = spec.partition("@")
        images.append((int(at, 0) if at else a.addr, open(path, "rb").read(), path))
    for addr, image, path in images:
        s.write(b"W %x %x\n" % (addr, len(image)))
        t0 = time.time()
        for i in range(0, len(image), 256):
            s.write(image[i:i + 256])
            s.flush()
        line = s.readline().decode(errors="replace").strip().lstrip("> ")
        want = "OK %08X" % (sum(image) & 0xFFFFFFFF)
        if line != want:
            print("%s: checksum mismatch: got %r want %r" % (path, line, want), file=sys.stderr)
            return 1
        print("loaded %s: %d bytes at 0x%x in %.0f s, checksum ok" % (path, len(image), addr, time.time() - t0))
    if not a.no_run:
        s.write(b"G %x\n" % (a.run if a.run is not None else images[0][0]))
        end = time.time() + a.listen
        while time.time() < end:
            d = s.read(256)
            if d:
                sys.stdout.write(d.decode(errors="replace"))
                sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
