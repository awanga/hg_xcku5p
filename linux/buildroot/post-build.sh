#!/bin/sh
# SPDX-License-Identifier: MIT
# Run by Buildroot with the target dir as $1. The kernel does not mount devtmpfs for an initramfs root, so busybox init
# must do it before anything touches /dev.
set -eu
sed -i '0,/^::sysinit:/s||::sysinit:/bin/mount -t devtmpfs devtmpfs /dev\n::sysinit:|' "$1/etc/inittab"
grep -q 'mount -t devtmpfs' "$1/etc/inittab"
# The SD root is flash: no access-time writes, and the journal commits every 60 s instead of 5 s. busybox `mount -o remount`
# ignores the fstab options, so init's remount of / is given them explicitly; fstab carries them for later `mount -a` runs.
sed -i 's|^::sysinit:/bin/mount -o remount,rw /$|::sysinit:/bin/mount -o remount,rw,noatime /|' "$1/etc/inittab"
grep -q 'remount,rw,noatime' "$1/etc/inittab"
sed -i 's|^/dev/root\t.*|/dev/root\t/\text4\trw,noauto,noatime,commit=60\t0\t1|' "$1/etc/fstab"
grep -q 'noatime,commit=60' "$1/etc/fstab"
