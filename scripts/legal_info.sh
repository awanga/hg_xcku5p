#!/bin/bash
# SPDX-License-Identifier: MIT
# Produce the Buildroot legal-info set (licenses, license texts, source archives, manifest) for the root filesystem in build/linux/br and copy
# the package manifest to docs/legal/rootfs-manifest.csv. The sources/ tree (hundreds of MB) is a release artifact, not committed.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
make -C "$here/build/third_party/buildroot" O="$here/build/linux/br" legal-info
cp "$here/build/linux/br/legal-info/manifest.csv" "$here/docs/legal/rootfs-manifest.csv"
echo "manifest: docs/legal/rootfs-manifest.csv; full set: build/linux/br/legal-info (sha256 in legal-info.sha256)"
