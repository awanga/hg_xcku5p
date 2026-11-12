#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check linux/rootfs/fan-governor against an independent model of its stated policy.

Policy (from the header of the script): stopped below T_OFF=40 C, restarts at T_ON=45 C (hysteresis), runs at MIN_DUTY=77 from T_ON and rises
linearly to 255 at T_MAX=70 C, speed up at once, down by at most STEP_DOWN=10 per cycle; die temperature from the SYSMONE4 code is
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


def model_target(t_c, cur):
    if t_c >= 70.0:
        return 255
    if t_c >= 45.0:
        return int(77 + (255 - 77) * (t_c - 45.0) / 25.0 + 1e-9)
    if cur > 0 and t_c >= 40.0:
        return 77
    return 0


def model_next(t_c, cur):
    want = model_target(t_c, cur)
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

# duty policy over temperatures and starting duties (including the hysteresis band and the ramp-down limit)
for t_mc in (20000, 39999, 40000, 42000, 44999, 45000, 50000, 57500, 69999, 70000, 90000):
    for cur in (0, 40, 77, 120, 255):
        got, _ = sh("next_duty %d %d" % (t_mc, cur))
        check("next_duty(%d mC, %d)" % (t_mc, cur), got, str(model_next(t_mc / 1000.0, cur)))

# a rising then falling sweep, feeding each result back in (hysteresis and ramp-down together)
cur_sh = cur_model = 0
for t_c in list(range(30, 80, 2)) + list(range(80, 30, -2)):
    got, _ = sh("next_duty %d %d" % (t_c * 1000, cur_sh))
    cur_model = model_next(float(t_c), cur_model)
    check("sweep at %d C" % t_c, got, str(cur_model))
    cur_sh = int(got)

print(
    "fan_governor_test checks=%d errors=%d %s"
    % (checks, errors, "PASS" if checks and not errors else "FAIL")
)
sys.exit(1 if errors or not checks else 0)
