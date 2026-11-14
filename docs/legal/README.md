# Legal and source manifest

Generated 2026-11-13 with `scripts/legal_info.sh` (Buildroot `make legal-info`).

- Root filesystem packages and licences: `rootfs-manifest.csv` (busybox GPL-2.0, musl MIT, i2c-tools GPL-2.0+/LGPL-2.1+, ethtool GPL-2.0, evtest GPL-2.0+, iperf3 BSD, toolchain GCC with runtime exception).
  The matching source archives and licence texts are in `build/linux/br/legal-info/{sources,licenses}` and ship with a release as `legal-info.tar` (about 245 MB of sources); GPL components therefore come with source.
- Not in the Buildroot set (built outside it, pinned in `docs/versions.md`): Linux v6.18.59 (GPL-2.0 with the syscall note; one local patch under `linux/patches/`), OpenSBI v1.9 (BSD-2-Clause),
  VexiiRiscv (MIT), LiteEth/LiteX (BSD-2-Clause). Vivado and AMD IP (DDR4, clock converter, crossbar, IIC, UART Lite) are AMD proprietary; the bitstream is distributed, the tools and IP sources are not.
- Project files: MIT (`LICENSE`); see `docs/licensing.md`.
