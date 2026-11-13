#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check linux/rootfs/fan-governor against an independent model of its stated policy.

Policy (from the header of the script): points (C, duty) (30,38) (45,61) | (45,77) (65,128) | (65,128) (80,217) | (80,217) (85,255),
0 below 30 C and 255 from 85 C; the curve sees a temperature that follows a rise at once and a fall only once it is HYST=4 C below the
held value; duty falls by at most STEP_DOWN=10 per cycle; die temperature from the SYSMONE4 code is
code * 509.3140064 / 65536 - 280.2308787 degC; invalid readings give full speed.
usage: fan_governor_test.py [script]  (default: linux/rootfs/fan-governor); exit 1 on any mismatch."""

import os
import subprocess
import sys

script = (
    sys.argv[1]
    if len(sys.argv) > 1
    else os.path.join(os.path.dirname(__file__), "../../linux/rootfs/fan-governor")
)


SEGS = [
    (85.0, None, None),
    (80.0, (80, 85), (217, 255)),
    (65.0, (65, 80), (128, 217)),
    (45.0, (45, 65), (77, 128)),
    (30.0, (30, 45), (38, 61)),
]


def model_target(t_c):
    for lo, (tr, dr) in ((s[0], (s[1], s[2])) for s in SEGS):
        if t_c >= lo:
            if tr is None:
                return 255
            return int(dr[0] + (dr[1] - dr[0]) * (t_c - tr[0]) / (tr[1] - tr[0]) + 1e-9)
    return 0


def model_held(t_c, held):
    if t_c > held:
        return t_c
    if t_c < held - 4.0:
        return t_c + 4.0
    return held


def model_next(t_c, cur):
    want = model_target(t_c)
    if want < cur:
        want = max(want, cur - 10)
    return want


def sh(expr):
    env = dict(os.environ, FAN_GOV_LIB="1")
    out = subprocess.run(
        ["sh", "-c", '. "%s"; %s' % (script, expr)], env=env, capture_output=True, text=True
    )
    return out.stdout.strip(), out.returncode


errors = checks = 0


def check(what, got, want):
    global errors, checks
    checks += 1
    if got != want:
        errors += 1
        print("FAIL %s: got %r want %r" % (what, got, want))


# temperature conversion: shell integer math against the float transfer function, within 1 mC
for code in (1, 1000, 32768, 40000, 42490, 48000, 65534):
    got, _ = sh("die_temp_mC %d" % code)
    want = code * 509.3140064 / 65536 - 280.2308787
    checks += 1
    if abs(int(got) - round(want * 1000)) > 1:
        errors += 1
        print("FAIL conversion code %d: got %s mC, model %.1f mC" % (code, got, want * 1000))

# duty policy over (held) temperatures and starting duties, including the ramp-down limit and every segment boundary
for t_mc in (
    20000,
    29999,
    30000,
    37500,
    44999,
    45000,
    55000,
    64999,
    65000,
    72500,
    79999,
    80000,
    82500,
    84999,
    85000,
    90000,
):
    for cur in (0, 40, 77, 120, 255):
        got, _ = sh("next_duty %d %d" % (t_mc, cur))
        check("next_duty(%d mC, %d)" % (t_mc, cur), got, str(model_next(t_mc / 1000.0, cur)))

# hysteresis: temperature sequences feeding each result back in
for seq, _start in (([40, 44, 43, 41, 39, 38, 37, 36, 50, 49, 47, 45, 44], 20.0),):
    held_sh, held_m = -100000, -100.0
    for t_c in seq:
        got, _ = sh("held_temp %d %d" % (t_c * 1000, held_sh))
        held_m = model_held(float(t_c), held_m)
        check("held_temp at %d C" % t_c, got, str(int(round(held_m * 1000))))
        held_sh = int(got)

# a rising then falling sweep through the whole governor chain (hysteresis and ramp-down together)
cur_sh = cur_model = 0
held_sh, held_m = -100000, -100.0
for t_c in list(range(20, 95, 2)) + list(range(95, 20, -2)):
    got_h, _ = sh("held_temp %d %d" % (t_c * 1000, held_sh))
    held_m = model_held(float(t_c), held_m)
    check("sweep held at %d C" % t_c, got_h, str(int(round(held_m * 1000))))
    held_sh = int(got_h)
    got, _ = sh("next_duty %d %d" % (held_sh, cur_sh))
    cur_model = model_next(held_m, cur_model)
    check("sweep duty at %d C" % t_c, got, str(cur_model))
    cur_sh = int(got)

print(
    "fan_governor_test checks=%d errors=%d %s"
    % (checks, errors, "PASS" if checks and not errors else "FAIL")
)
sys.exit(1 if errors or not checks else 0)
