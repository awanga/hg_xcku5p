#!/bin/bash
# SPDX-License-Identifier: MIT
# Fan governor policy test and mutants: the test must pass on the script and fail on each mutant.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
gov=$here/linux/rootfs/fan-governor
b=${BUILD:-$here/build/tests_rootfs}
mkdir -p "$b"
fail=0
python3 "$here/tests/rootfs/fan_governor_test.py" "$gov" >"$b/gov.log" 2>&1 && echo "PASS fan_governor" || { echo "FAIL fan_governor"; tail -3 "$b/gov.log"; fail=1; }
mutant() { # name sed-expression
	sed "$2" "$gov" >"$b/mut_$1"
	cmp -s "$gov" "$b/mut_$1" && { echo "FAIL mutant $1 unchanged"; fail=1; return; }
	python3 "$here/tests/rootfs/fan_governor_test.py" "$b/mut_$1" >"$b/mut_$1.log" 2>&1 && { echo "FAIL mutant $1 not detected"; fail=1; } || echo "PASS mutant $1 detected"
}
mutant nohyst 's/elif \[ "\$cur" -gt 0 \] && \[ "\$t" -ge "\$T_OFF" \]; then/elif false; then/'
mutant norampdown 's/\[ "\$want" -lt "\$floor" \] && want=\$floor/:/'
mutant mindutyoff 's/echo \$((MIN_DUTY + (255 - MIN_DUTY)/echo $((MIN_DUTY + 1 + (255 - MIN_DUTY)/'
mutant slope 's/509314 \/ 65536/501374 \/ 65536/'
mutant span 's|/ (T_MAX - T_ON)))|/ (T_MAX - T_OFF)))|'
exit $fail
