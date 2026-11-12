#!/bin/bash
# SPDX-License-Identifier: MIT
# Fetch the external sources the build needs into build/third_party at the commits pinned in docs/versions.md,
# and apply the local patches. Re-running verifies the pins and leaves existing checkouts alone.
# usage: scripts/fetch_sources.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
tp=$here/build/third_party
mkdir -p "$tp"

# name url commit (keep in sync with docs/versions.md)
sources="
VexiiRiscv https://github.com/SpinalHDL/VexiiRiscv.git 0dc189e1335d7ad0739c3298de09fcb3d2b956d4
linux https://github.com/gregkh/linux.git 1253a6aa5d104312bf0992afacc15220ae35bdf9
opensbi https://github.com/riscv-software-src/opensbi.git cbf9f6734dd85a982c63e3cb5db7ffe09da839ca
buildroot https://github.com/buildroot/buildroot.git 679b9ead7620bbf193620d1ebf56f53c1764d37a
liteeth_up https://github.com/enjoy-digital/liteeth.git 3143d3002bef46a2241210076712be43332ea088
litex_up https://github.com/enjoy-digital/litex.git acbc4634eabe65a571e1fa4e1907c4c035454d34
"

echo "$sources" | while read -r name url commit; do
	[ -n "$name" ] || continue
	d=$tp/$name
	if [ ! -d "$d/.git" ]; then
		git init -q "$d"
		git -C "$d" remote add origin "$url"
	fi
	if [ "$(git -C "$d" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]; then
		git -C "$d" fetch -q --depth 1 origin "$commit"
		git -C "$d" checkout -q --detach FETCH_HEAD
	fi
	got=$(git -C "$d" rev-parse HEAD)
	[ "$got" = "$commit" ] || { echo "FAIL $name: $got != $commit" >&2; exit 1; }
	echo "ok $name $commit"
done

# Local patches (fpga/patches): applied once; skipped if already present.
v=$tp/VexiiRiscv
p=$here/fpga/patches/vexii-l2-blackbox.patch
if git -C "$v" apply --check -R "$p" 2>/dev/null; then
	echo "patch already applied: $(basename "$p")"
else
	git -C "$v" apply "$p"
	echo "patch applied: $(basename "$p")"
fi

# Local Linux patches (linux/patches): applied once; skipped if already present.
for p in "$here"/linux/patches/*.patch; do
	if git -C "$tp/linux" apply --check -R "$p" 2>/dev/null; then
		echo "patch already applied: $(basename "$p")"
	else
		git -C "$tp/linux" apply "$p"
		echo "patch applied: $(basename "$p")"
	fi
done
