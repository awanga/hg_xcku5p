#!/bin/sh
# SPDX-License-Identifier: MIT
# Run by Buildroot with the target dir as $1. The kernel does not mount devtmpfs for an initramfs root, so busybox init
# must do it before anything touches /dev.
set -eu
sed -i '0,/^::sysinit:/s||::sysinit:/bin/mount -t devtmpfs devtmpfs /dev\n::sysinit:|' "$1/etc/inittab"
grep -q 'mount -t devtmpfs' "$1/etc/inittab"
