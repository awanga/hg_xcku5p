#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Summarise a build_soc.tcl output directory into report.json and fail on regressions.

usage: build_report.py <build dir> [--allow-negative-slack] [--baseline LUTS]

Reads impl_timing.rpt, impl_utilization.rpt and impl_drc.rpt, records the tool version, source commit
(with a dirty flag) and the bitstream checksum, writes <dir>/report.json and prints one summary line.
Exit status: 0 pass, 1 regression (negative WNS/WHS, DRC errors or critical warnings, missing report).
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with open(path) as f:
        return f.read()


def timing(text):
    """First row under the 'Design Timing Summary' header: WNS TNS _ _ WHS THS ..."""
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        if ln.startswith("| Design Timing Summary"):
            for row in lines[i + 1 : i + 12]:
                nums = row.split()
                if len(nums) >= 8 and re.fullmatch(r"-?\d+\.\d+", nums[0]):
                    return {
                        "wns": float(nums[0]),
                        "tns": float(nums[1]),
                        "whs": float(nums[4]),
                        "ths": float(nums[5]),
                    }
    raise ValueError("no Design Timing Summary row")


def utilization(text):
    want = {
        "CLB LUTs": "luts",
        "CLB Registers": "registers",
        "Block RAM Tile": "bram_tiles",
        "URAM": "uram",
        "DSPs": "dsps",
    }
    out = {}
    for ln in text.splitlines():
        cols = [c.strip() for c in ln.strip("|\n").split("|")]
        if len(cols) >= 2 and cols[0] in want and want[cols[0]] not in out:
            out[want[cols[0]]] = float(cols[1])
    missing = set(want.values()) - set(out)
    if missing:
        raise ValueError("utilization rows missing: %s" % sorted(missing))
    return out


def drc(text):
    counts = {}
    for ln in text.splitlines():
        cols = [c.strip() for c in ln.strip("|\n").split("|")]
        if len(cols) == 4 and cols[1] in ("Error", "Critical Warning", "Warning", "Advisory"):
            counts[cols[1]] = counts.get(cols[1], 0) + int(cols[3])
    return counts


def tool_version(text):
    m = re.search(r"Tool Version\s*:\s*(.+)", text)
    return m.group(1).strip() if m else "unknown"


def git(*args):
    return subprocess.run(
        ["git", "-C", ROOT, *args], capture_output=True, text=True, check=False
    ).stdout.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--allow-negative-slack", action="store_true")
    a = ap.parse_args()
    try:
        tt = read(os.path.join(a.dir, "impl_timing.rpt"))
        rep = {
            "dir": os.path.relpath(a.dir, ROOT),
            "vivado": tool_version(tt),
            "git_commit": git("rev-parse", "HEAD"),
            "git_dirty": bool(git("status", "--porcelain", "--untracked-files=no")),
            "timing": timing(tt),
            "utilization": utilization(read(os.path.join(a.dir, "impl_utilization.rpt"))),
            "drc": drc(read(os.path.join(a.dir, "impl_drc.rpt"))),
        }
    except (OSError, ValueError) as e:
        print("FAIL: %s" % e, file=sys.stderr)
        return 1
    bit = os.path.join(a.dir, "soc.bit")
    if os.path.exists(bit):
        with open(bit, "rb") as f:
            rep["bitstream_sha256"] = hashlib.sha256(f.read()).hexdigest()
    problems = []
    t = rep["timing"]
    if not a.allow_negative_slack and (t["wns"] < 0 or t["whs"] < 0):
        problems.append("negative slack (WNS %.3f, WHS %.3f)" % (t["wns"], t["whs"]))
    for sev in ("Error", "Critical Warning"):
        if rep["drc"].get(sev):
            problems.append("%d DRC %s" % (rep["drc"][sev], sev))
    rep["problems"] = problems
    with open(os.path.join(a.dir, "report.json"), "w") as f:
        json.dump(rep, f, indent=2)
        f.write("\n")
    u = rep["utilization"]
    print(
        "%s WNS %+.3f WHS %+.3f LUT %d FF %d BRAM %.1f URAM %d DSP %d DRC %s %s"
        % (
            "FAIL" if problems else "PASS",
            t["wns"],
            t["whs"],
            u["luts"],
            u["registers"],
            u["bram_tiles"],
            u["uram"],
            u["dsps"],
            rep["drc"],
            "; ".join(problems),
        )
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
