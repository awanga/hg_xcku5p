#!/bin/bash
# SPDX-License-Identifier: MIT
# Checks that need neither Vivado nor the board (run by .github/workflows/pr.yml and locally before a commit).
# usage: scripts/ci.sh [--quick]   (--quick skips the RTL simulation suite)
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here" || exit 1
fail=0
step() { # name command...
	local n=$1
	shift
	if "$@" >"build/ci_$n.log" 2>&1; then echo "PASS $n"; else
		echo "FAIL $n (build/ci_$n.log)"
		tail -5 "build/ci_$n.log"
		fail=1
	fi
}
mkdir -p build

shells=$(git ls-files '*.sh')
c_files=$(git ls-files 'fw/*.c' 'fw/*.h' 'tests/*.c')
# shellcheck disable=SC2086
step shellcheck shellcheck -S warning $shells
# shellcheck disable=SC2086
step clang-format clang-format --dry-run --Werror $c_files
step ruff-check ruff check . --exclude build
step ruff-format ruff format --check . --exclude build
step dts bash tests/dts/run.sh
step rootfs bash tests/rootfs/run.sh
[ "${1:-}" = "--quick" ] || step rtl bash tests/rtl/run.sh

[ $fail -eq 0 ] && echo "CI PASS"
exit $fail
