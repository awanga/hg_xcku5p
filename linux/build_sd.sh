#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the SD-root boot payload and card image: kernel (no initramfs), device tree, OpenSBI, and build/linux/sdcard.img.
# usage: linux/build_sd.sh   (needs build/linux/br from Buildroot and the sources under build/third_party)
# KDEBUG=1 adds dynamic debug to the kernel for driver bring-up; DATA_MIB sets the data partition size (default 256).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
b=$here/build/linux
src=$here/build/third_party/linux
cross=$b/br/host/bin/riscv64-buildroot-linux-musl-
KDEBUG=${KDEBUG:-0} "$here/linux/kernel/configure.sh" "$src" "$b/kernel_sd" "$cross" ""
make -C "$src" ARCH=riscv CROSS_COMPILE="$cross" O="$b/kernel_sd" -j8 Image >"$b/kernel_sd.log" 2>&1
cpp -nostdinc -undef -x assembler-with-cpp -I"$here/linux/dts" "$here/linux/dts/hg-xcku5p-sdroot.dts" |
	dtc -I dts -O dtb -o "$b/hg-xcku5p-sdroot.dtb" -
make -C "$here/build/third_party/opensbi" O="$b/opensbi_sd" CROSS_COMPILE="$cross" PLATFORM=generic \
	PLATFORM_RISCV_XLEN=64 PLATFORM_RISCV_ISA=rv64ima_zicsr_zifencei PLATFORM_RISCV_ABI=lp64 \
	FW_TEXT_START=0x40100000 FW_JUMP_ADDR=0x40200000 FW_JUMP_FDT_ADDR=0x41f00000 \
	FW_FDT_PATH="$b/hg-xcku5p-sdroot.dtb" -j8 >"$b/opensbi_sd.log" 2>&1
# The root is never written, so it needs no journal (a journal would also force a recovery write at mount after a clean image).
cp "$b/br/images/rootfs.ext4" "$b/rootfs_ro.ext4"
e2fsck -fy "$b/rootfs_ro.ext4" >/dev/null || [ $? -lt 4 ]
tune2fs -O ^orphan_file,^has_journal "$b/rootfs_ro.ext4" >/dev/null
e2fsck -fn "$b/rootfs_ro.ext4" >/dev/null
rm -f "$b/data.ext4"
truncate -s "${DATA_MIB:-256}M" "$b/data.ext4"
mke2fs -q -t ext4 -L data -E root_owner=0:0 "$b/data.ext4"
python3 "$here/tools/mkcard.py" "$b/sdcard.img" --fw "$b/opensbi_sd/platform/generic/firmware/fw_jump.bin" \
	--kernel "$b/kernel_sd/arch/riscv/boot/Image" --dtb "$b/hg-xcku5p-sdroot.dtb" --rootfs "$b/rootfs_ro.ext4" --data "$b/data.ext4"
