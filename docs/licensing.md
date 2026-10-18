# Licensing

Project license: **MIT** (`LICENSE`), chosen 2026-10-18. SPDX header: `SPDX-License-Identifier: MIT` in project-authored
source files (comments/docs excepted).

## Dependency interaction (checked 2026-10-18 against upstream LICENSE files unless noted)

| Dependency | License | Interaction with an MIT repo |
|---|---|---|
| VexRiscv | MIT (GitHub API) | Compatible; keep notice if vendored. |
| VexiiRiscv | MIT (GitHub API) | Compatible. |
| CVA6 | Solderpad Hardware License v0.51 (Apache-2.0-style, hardware patent grant) | Permissive; compatible. Retain its LICENSE/NOTICE and file headers; cannot be relicensed to MIT. |
| SpinalHDL | core LGPL, lib MIT (upstream LICENSE) | Used as a generator tool; generated Verilog is a tool output, but confirm the emitted lib components' licenses when pinning. |
| LiteX | BSD-2-Clause | Compatible. linux-on-litex-vexriscv: BSD-2-Clause. |
| Linux kernel, local patches | GPL-2.0-only (+ syscall note) | Not MIT: files under `linux/patches/` carry GPL-2.0 SPDX. Device-tree sources: `GPL-2.0 OR MIT` (upstream norm). Kernel/rootfs binaries are distributed under their own licenses. |
| Buildroot | GPL-2.0-or-later | The BR2_EXTERNAL tree can be MIT; patches to packages follow each package's license. Release images must ship source/offer for GPL components. |
| AMD Vivado / IP (DDR4 MIG, etc.) | AMD proprietary EULA | Never commit tools or IP sources; generated bitstreams are fine to distribute (check IP terms per core, e.g. any evaluation-license IP). Not covered by MIT. |
| Board schematic (`docs/external/`) | Unknown, vendor | Not committed (gitignored). |

## Conclusion
No compelling reason to deviate: every candidate CPU and tool is MIT/BSD/SHL-compatible. The exceptions above are
per-directory SPDX exceptions, not a reason for a different top-level license. Revisit if a copyleft HDL core (GPL/LGPL
RTL linked into the bitstream) is adopted.
