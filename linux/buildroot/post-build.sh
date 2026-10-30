#!/bin/sh
# SPDX-License-Identifier: MIT
# Run by Buildroot with the target dir as $1 (the same dir is reused across runs, so every edit must be idempotent).
set -eu
inittab=$1/etc/inittab
fstab=$1/etc/fstab

# The kernel does not mount devtmpfs for an initramfs root, so busybox init must do it before anything touches /dev. A real
# root (SD) already has it mounted by the kernel, where the mount fails with EBUSY; that case is expected and silenced.
sed -i '/mount -t devtmpfs/d' "$inittab"
sed -i '0,/^::sysinit:/s||::sysinit:/bin/sh -c "/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null; true"\n::sysinit:|' "$inittab"
grep -q 'mount -t devtmpfs' "$inittab"

# The SD root is read-only (mounted ro by the kernel command line) so a power cut cannot corrupt it. An initramfs root is
# already writable, so init's default remount is not needed in either case.
sed -i '/^::sysinit:\/bin\/mount -o remount,rw/d' "$inittab"
! grep -q 'remount,rw' "$inittab"

# Persistent state lives on the second SD partition: journalled, noatime, journal committed every 60 s to limit flash wear.
# /dev/mmcblk0p2 is absent for an initramfs boot and `mount -a` then reports an error that is harmless.
sed -i 's|^/dev/root\t.*|/dev/root\t/\text4\tro,noauto\t0\t0|' "$fstab"
grep -q '^/dev/root.*ro,noauto' "$fstab"
grep -q '^/dev/mmcblk0p2' "$fstab" ||
	printf '/dev/mmcblk0p2\t/data\text4\trw,noatime,commit=60\t0\t0\n' >>"$fstab"
mkdir -p "$1/data"

# root's home is bind-mounted from the data partition so shell history and files survive reboots.
cat >"$1/etc/init.d/S03data" <<'SCRIPT'
#!/bin/sh
case "$1" in
start)
	if grep -q ' /data ' /proc/mounts; then
		mkdir -p /data/root
		chmod 700 /data/root
		mount --bind /data/root /root
	fi
	;;
esac
SCRIPT
chmod 755 "$1/etc/init.d/S03data"
