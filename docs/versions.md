# Versions and external sources

| Item | Version / pin | Source | Support / policy | Reviewed |
|---|---|---|---|---|
| AMD Vivado | 2026.1 (/opt/Xilinx/2026.1), free ML Standard node license via XILINXD_LICENSE_FILE; verified 2026-10-18 by scripts/check-env.sh (synth->bitstream for xcku5p-ffvb676-2-i) | AMD | pin per release build | 2026-10-18 |
| Linux kernel | v6.18.59 (LTS), commit 1253a6aa5d104312bf0992afacc15220ae35bdf9 | github.com/gregkh/linux (stable mirror of kernel.org) | LTS; check EOL at kernel.org/category/releases.html | 2026-10-29 |
| OpenSBI | v1.9, commit cbf9f6734dd85a982c63e3cb5db7ffe09da839ca | github.com/riscv-software-src/opensbi | upstream releases | 2026-10-29 |
| Buildroot | 2026.02.3 (LTS series), commit 679b9ead7620bbf193620d1ebf56f53c1764d37a | github.com/buildroot/buildroot | LTS series 2026.02.x | 2026-10-29 |
| LiteEth (MAC) | commit 3143d3002bef46a2241210076712be43332ea088 (master, 173 commits after tag 2026.08) | github.com/enjoy-digital/liteeth | pinned to a commit, not a release: tags up to 2026.08 and PyPI 2024.12 never flag CRC errors on the 8-bit GMII path (CRC checker `be` undriven); fixed on master by the stream `last_be` refactor (c52415c). Move to the first release containing it | 2026-10-30 |
| LiteX | commit acbc4634eabe65a571e1fa4e1907c4c035454d34 (master) | github.com/enjoy-digital/litex | must match the LiteEth commit | 2026-10-30 |
| CPU core | VexiiRiscv commit 0dc189e1335d7ad0739c3298de09fcb3d2b956d4 (master) plus fpga/patches/vexii-l2-blackbox.patch (L2 as a black box so it maps to UltraRAM) | github.com/SpinalHDL/VexiiRiscv | pinned to a commit, no release tags used; the patch is local, not upstreamed (see decisions/0006) | 2026-11-12 |
| Verilator | 5.032 (Debian) | distro package | simulation and lint only | 2026-11-12 |
| Icarus Verilog | 12.0 | distro package | unit tests | 2026-11-12 |
| Yosys / SymbiYosys | 0.52 / local sby | distro / local | no formal harness committed yet | 2026-11-12 |
| openFPGALoader | board access (JTAG, flash); see docs/validation/flash-boot.md for the options used | github.com/trabucayre/openFPGALoader | local tool, version not pinned yet | 2026-11-12 |

Sources are fetched at these commits by `scripts/fetch_sources.sh` (keep the script and this table in sync).
VexRiscv-SMP (pythondata-cpu-vexriscv_smp 0b753ec) and CVA6 (2ef1c1b) were used for the CPU study only and are not part of any build.

Policy: no release build may depend on a moving branch; add hashes when sources are fetched.
