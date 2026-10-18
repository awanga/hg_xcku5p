# Versions and external sources

| Item | Version / pin | Source | Support / policy | Reviewed |
|---|---|---|---|---|
| AMD Vivado | 2026.1 (/opt/Xilinx/2026.1), free ML Standard node license via XILINXD_LICENSE_FILE; verified 2026-10-18 by scripts/check-env.sh (synth->bitstream for xcku5p-ffvb676-2-i) | AMD | pin per release build | 2026-10-18 |
| Linux kernel | TBD at kickoff (newest LTS supporting the chosen CPU) | kernel.org | record release URL + EOL | — |
| Buildroot | TBD (README: 2025.02 LTS series, re-check) | buildroot.org | record hash | — |
| CPU core | TBD (VexRiscv/VexiiRiscv or CVA6) | upstream | pin commit | — |

Policy: no release build may depend on a moving branch; add hashes when sources are fetched.
