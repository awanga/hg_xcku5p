#!/bin/bash
# SPDX-License-Identifier: MIT
# Package release artifacts with a manifest and SHA-256 checksums. Nothing is published or tagged here.
# usage: scripts/release.sh <version> <flash-ready.bit> [outdir]
#   <flash-ready.bit> comes from fpga/scripts/flash_bit.tcl (the bitstream that goes into the config flash).
# Reads build/linux (build_sd.sh output) and the pins in docs/versions.md; refuses a dirty tree.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 2 ] || { echo "usage: $0 <version> <flash-ready.bit> [outdir]" >&2; exit 2; }
ver=$1
bit=$2
out=${3:-$here/build/release/$ver}
b=$here/build/linux

if [ -n "$(git -C "$here" status --porcelain --untracked-files=no)" ] && [ -z "${ALLOW_DIRTY:-}" ]; then
	echo "refusing to package from a dirty tree (ALLOW_DIRTY=1 overrides, the manifest then says so)" >&2
	exit 1
fi
files="
$bit bitstream/soc.bit
$b/opensbi_sd/platform/generic/firmware/fw_jump.bin boot/fw_jump.bin
$b/kernel_sd/arch/riscv/boot/Image boot/Image
$b/hg-xcku5p-sdroot.dtb boot/hg-xcku5p-sdroot.dtb
$b/rootfs_ro.ext4 rootfs/rootfs_ro.ext4
$b/br/build/packages-file-list.txt rootfs/package-file-list.txt
$here/docs/versions.md docs/versions.md
$here/docs/validation/flash-boot.md docs/recovery-flash-boot.md
$here/factory/README.md docs/recovery-factory.md
$here/factory/restore.sh recovery/restore.sh
$here/factory/vendor_flash_16MiB.sha256 recovery/vendor_flash_16MiB.sha256
"
rm -rf "$out"
mkdir -p "$out"
missing=0
echo "$files" | while read -r src dst; do
	[ -n "$src" ] || continue
	if [ ! -f "$src" ]; then echo "missing: $src" >&2; exit 1; fi
	mkdir -p "$out/$(dirname "$dst")"
	cp "$src" "$out/$dst"
done || missing=1
[ $missing -eq 0 ] || { echo "release incomplete, see above" >&2; exit 1; }

{
	echo "version: $ver"
	echo "git_commit: $(git -C "$here" rev-parse HEAD)"
	echo "git_dirty: $([ -n "$(git -C "$here" status --porcelain --untracked-files=no)" ] && echo yes || echo no)"
	echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "vivado: ${VIVADO_VERSION:-$(vivado -version 2>/dev/null | head -1 || echo unknown)}"
	echo "soc_netlist: soc_l2u_128k_w4 (fpga/scripts/cpu/gen_default_soc.sh)"
	echo "sources: see docs/versions.md (fetched by scripts/fetch_sources.sh)"
	echo "recovery: docs/recovery-flash-boot.md, docs/recovery-factory.md"
} >"$out/MANIFEST.txt"
(cd "$out" && find . -type f ! -name SHA256SUMS | sort | xargs sha256sum >SHA256SUMS)
(cd "$out" && sha256sum --quiet -c SHA256SUMS)
echo "release $ver in $out ($(wc -l <"$out/SHA256SUMS") files)"
