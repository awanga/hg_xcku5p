# 0002 — Buildroot for the Linux userspace and toolchain

- Status: accepted (README recommendation, in use since 2026-10-29; the owner was not asked separately and has not objected)
- Date: 2026-11-12 (written after the fact; the choice dates from 2026-10-29)

## Context
One board, one CPU core, a small rootfs (the first image is 2 MB), and a small local patch set. The README trade study (section "Linux build-system trade study")
compares Buildroot and Yocto on maintenance cost, reproducibility, LTS horizon, package model and fit.

## Alternatives
- Yocto Project: longer support horizon (Wrynose LTS, April 2030) and package feeds, but more metadata and a higher learning and maintenance cost for one product.

## Decision
Buildroot 2026.02.3 (LTS series 2026.02.x, commit in docs/versions.md), musl toolchain built by Buildroot, config in `linux/buildroot/hg_xcku5p_defconfig` with
`post-build.sh`. Linux (v6.18.59 LTS) and OpenSBI (v1.9) are built outside Buildroot by `linux/kernel/configure.sh` and `linux/build_sd.sh`, so the kernel and
boot-firmware integration stay separate from the userspace build.

## Consequences
- Upgrades follow the Buildroot LTS point releases; moving to a new LTS series is a deliberate, tested change recorded in docs/versions.md.
- The image has no package manager; changes are a rebuild plus a new SD image.
- Moving to Yocto later only replaces the userspace build; the hardware layer (RTL, device tree, boot flow) is independent.

## Validation
Boots on the board from SD and flash-loaded bitstreams (docs/validation/linux-bringup.md). Reproducibility from a clean checkout: `scripts/fetch_sources.sh` pins the
sources; the full Buildroot rebuild from scratch has not been repeated since the first build.

## Revisit when
A package-managed runtime, several product variants, or a formal long-term support commitment becomes a requirement, or the Buildroot LTS series reaches end of support (March 2028 per the README).
