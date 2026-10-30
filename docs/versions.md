# Versions and external sources

| Item | Version / pin | Source | Support / policy | Reviewed |
|---|---|---|---|---|
| AMD Vivado | 2026.1 (/opt/Xilinx/2026.1), free ML Standard node license via XILINXD_LICENSE_FILE; verified 2026-10-18 by scripts/check-env.sh (synth->bitstream for xcku5p-ffvb676-2-i) | AMD | pin per release build | 2026-10-18 |
| Linux kernel | v6.18.59 (LTS), commit 1253a6aa5d104312bf0992afacc15220ae35bdf9 | github.com/gregkh/linux (stable mirror of kernel.org) | LTS; check EOL at kernel.org/category/releases.html | 2026-10-29 |
| OpenSBI | v1.9, commit cbf9f6734dd85a982c63e3cb5db7ffe09da839ca | github.com/riscv-software-src/opensbi | upstream releases | 2026-10-29 |
| Buildroot | 2026.02.3 (LTS series), commit 679b9ead7620bbf193620d1ebf56f53c1764d37a | github.com/buildroot/buildroot | LTS series 2026.02.x | 2026-10-29 |
| LiteEth (MAC) | commit 3143d3002bef46a2241210076712be43332ea088 (master, 173 commits after tag 2026.08) | github.com/enjoy-digital/liteeth | pinned to a commit, not a release: tags up to 2026.08 and PyPI 2024.12 never flag CRC errors on the 8-bit GMII path (CRC checker `be` undriven); fixed on master by the stream `last_be` refactor (c52415c). Move to the first release containing it | 2026-10-30 |
| LiteX | commit acbc4634eabe65a571e1fa4e1907c4c035454d34 (master) | github.com/enjoy-digital/litex | must match the LiteEth commit | 2026-10-30 |
| CPU core | TBD (VexRiscv/VexiiRiscv or CVA6) | upstream | pin commit | — |

Policy: no release build may depend on a moving branch; add hashes when sources are fetched.
