#!/bin/bash
# SPDX-License-Identifier: MIT
# Development host setup for the NFS-root boot (linux/dts/hg-xcku5p-sdnfs.dts): unpack the Buildroot root filesystem into /srv/hg-rootfs and
# export it to the board's subnet. Needs root (run with sudo) and nfs-kernel-server. After a rebuild run it again to refresh the tree.
# usage: sudo scripts/nfs_dev_setup.sh [subnet]   (default 192.168.1.0/24)
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
net=${1:-192.168.1.0/24}
dir=/srv/hg-rootfs
tar=$here/build/linux/br/images/rootfs.tar
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
[ -f "$tar" ] || { echo "missing $tar (build Buildroot first)"; exit 1; }
mkdir -p "$dir"
tar -C "$dir" -xf "$tar"
line="$dir $net(rw,no_root_squash,no_subtree_check,async)"
grep -qxF "$line" /etc/exports || echo "$line" >>/etc/exports
exportfs -ra
exportfs -v | grep -F "$dir"
echo "exported $dir to $net"
