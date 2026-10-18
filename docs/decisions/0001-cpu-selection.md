# 0001 — CPU selection

- Status: finalists approved 2026-10-18 (VexiiRiscv, VexRiscv-SMP); final CPU choice pending measurements
- Date: 2026-10-18 (study started)

## Decisions recorded (user, 2026-10-18)
- Finalists approved: **VexiiRiscv** and **VexRiscv-SMP** (baseline). **CVA6 dropped**; its numbers below are kept as the reason.
- Prefer a **64-bit** CPU in general, but **minimize BRAM**: a larger BRAM footprint is accepted only for a sufficiently large
  measured performance gain (README acceptance rule). VexRiscv-SMP is RV32 only, so it remains the 32-bit/low-BRAM baseline.
- DDR4: prefer the AMD DDR4 IP and the existing bring-up work; **LiteDRAM `USPDDRPHY` stays an alternative**; the final choice
  waits for functional speed measured on hardware (see 0004). The SoC integration path follows from that choice (see below).
- Ethernet: LiteEth accepted (0003); other MACs (e.g. axi_ethernetlite) remain fallbacks.

## Context
Main CPU must run an upstream-LTS Linux with MMU on XCKU5P-FFVB676-2-i and leave fabric for custom AXI datapaths.
Scope (user decision 2026-10-18): VexRiscv/VexRiscv-SMP, VexiiRiscv, CVA6 (CVA6 later dropped, see above). MicroBlaze V and Rocket Chip were removed.
Upstream Linux supports RISC-V (RV32 and RV64, MMU) without a per-CPU port; a candidate needs M/A/S/U, Sv32 or Sv39, a PLIC and
a timer (CLINT/ACLINT or SBI timer), and an SBI firmware (OpenSBI). The core choice is mainly an integration, resource and
performance question.

## Candidates (facts as read 2026-10-18; sources in "Evidence")
| | VexRiscv-SMP (LiteX `vexriscv_smp`) | VexiiRiscv | CVA6 |
|---|---|---|---|
| ISA | RV32IMA(+F/D optional), Sv32 | RV32 or RV64, IMA(C)(FD), Sv32/Sv39, optional SMP/hypervisor/AIA | RV32 or RV64 IMAC(FD), Sv32/Sv39 |
| Maturity | Oldest; 1.0.1 tag; active commits (last push 2026-10-13); author points to VexiiRiscv | Active (last push 2026-10-09); only tag is `v0.0.0`, pin by commit | OpenHW; releases v5.3.0 (2025-02), cv32a60x-v6.0.0 (2025-04); active |
| Linux evidence | Linux-on-LiteX/VexRiscv for years (RV32 Buildroot) | README: Linux/Buildroot/Debian; LiteX variants `standard/cached/linux/debian`; docs for Buildroot/Debian/Alpine | Official SDK Genesys-2 (Kintex-7) Linux boot (RV64); LiteX variants standard/standard32/full |
| License | MIT | MIT (LGPL SpinalHDL generator, MIT lib) | SHL-2.0 / Apache-2.0 WITH SHL-2.0 (Flist header); submodules mixed; LICENSE file reads SHL 0.51 |
| Toolchain | Pre-generated Verilog in `pythondata-cpu-vexriscv_smp`; Scala only to regenerate | Scala/sbt + SpinalHDL submodule; JDK 25 worked here | Plain SystemVerilog (Vivado reads it); SDK needs RISC-V gcc, Spike etc. |
| Published perf | CoreMark 2.3-2.6/MHz, 1.4-1.6 DMIPS/MHz (README, Artix-7) | up to 5.24 CoreMark/MHz, 2.50 DMIPS/MHz (README, max-IPC config) | ~2.0 CoreMark/MHz (third-party thesis, Headsail); 2.1 design target |

## Measured: out-of-context synthesis, Vivado 2026.1, xcku5p-ffvb676-2-i, 8.0 ns clock (2026-10-18)
Synthesis only (no place/route, core + L1 caches, no peripherals, no I/O timing). WNS is pre-route and optimistic; do not read it as Fmax.
| Core (configuration) | CLB LUT | CLB FF | BRAM tiles | DSP | WNS @ 8 ns |
|---|---|---|---|---|---|
| VexRiscv SMP x1, RV32IMA, 8K/8K 2-way (`Cc1_Iw64Is8192Iy2_Dw64Ds8192Dy2_..._Ldw128_Cdma_Ood`) | 5763 | 5374 | 4 | 4 | +5.25 |
| VexiiRiscv RV32IMA, LiteX "linux" args, 16K/16K 4-way, BTB/RAS/gshare | 4420 | 3371 | 22 | 4 | +4.76 |
| VexiiRiscv RV64IMA, same args | 6359 | 4805 | 22 | 16 | +4.72 |
| CVA6 `cv32a6_imac_sv32` (FpgaEn=1), 16K I$ | 20575 | 7579 | 12 | 4 | -1.72 |
| CVA6 `cv64a6_imafdc_sv39` (FpgaEn=1), 16K I$/32K D$ | 41887 | 15541 | 0 (!) | 27 | -2.62 |
Caveats: (1) the CVA6 RV64 run reports 0 BRAM and 0.8k LUTRAM for 48 KB of cache, so its memories were mapped elsewhere or
pruned; treat that row as unreliable until re-run inside a wrapper. (2) Cache sizes and associativity differ between rows
(different defaults), so rows are not iso-config. (3) CVA6 RV32 also exceeds the 8 ns target pre-route.
(4) Percent of the device: Vexii RV32 = 2.0 % LUT; VexRiscv = 2.7 %; CVA6 RV32 = 9.5 %; CVA6 RV64 = 19 %.
Pins: VexiiRiscv dev `0dc189e`, SpinalHDL `58837d3`; CVA6 `v5.3.0` (`2ef1c1b`); pythondata-cpu-vexriscv_smp `0b753ec`.
Reproduce: `fpga/scripts/cpu/gen_vexii.sh`, `ooc_verilog.tcl`, `ooc_cva6.tcl` (arguments in docs/validation/cpu-ooc-synthesis.md).

## Preliminary assessment (not a decision)
- Applying the README acceptance rule: CVA6 RV32 costs about 4.6x the LUTs of VexiiRiscv RV32 for no published CPI advantage
  (published CoreMark/MHz is lower than Vexii's). It would need a measured multi-fold performance gain to qualify; none is known.
- VexiiRiscv is the smallest, has the strongest published IPC, MIT licence, and a documented Linux/LiteX path, but is a moving
  target (no release tags) and needs Scala to generate. VexRiscv-SMP is the lowest-risk RV32 baseline (pre-generated Verilog, long
  Linux history) at higher resource and lower IPC.
- Proposed finalists: **VexiiRiscv** (RV32 first; RV64 if userland needs it) and **VexRiscv-SMP** as baseline. Keep CVA6 in the
  study only until a corrected measurement and a CoreMark run show whether any performance gap justifies ~4x the fabric.
  **Needs user approval before CVA6 is dropped.**
- RV32 vs RV64 userland: Buildroot supports RV32 with glibc (>= 2.33); Debian does not target RV32. RV64 costs about 1.4x LUT and 12 more DSPs on Vexii.

## Open questions / next measurements
1. Integration path (see below). 2. CoreMark/Dhrystone per core on identical memory models (Verilator, bare-metal), then in Linux.
3. Implemented Fmax (place/route inside a minimal SoC with the DDR4 controller and AXI fabric) at 150/200/250 MHz targets.
4. Re-run CVA6 RV64 with caches visible; add an iso-cache comparison. 5. Debug path: FT232H JTAG is not Vivado-native.

## Integration path (decision needed before SoC work)
A. **LiteX SoC** (supported for all three; generates SoC, CSR map, DTS; liteuart/litex_mmc/liteeth drivers upstream). DDR4 through
   LiteDRAM `USPDDRPHY` (header says DDR4 up to 1866 MT/s, any width multiple of 8) instead of the AMD DDR4 IP; needs a >=300 MHz IDELAYCTRL clock.
B. **Vivado block design / hand SoC**: CPU as AXI master, AMD DDR4 IP (already built, see 0004), AMD AXI IP peripherals
   (uartlite, quad_spi, gpio, iic, ethernetlite) with upstream Linux drivers; needs a PLIC/CLINT (CVA6 has them in `corev_apu`; Vexii has a TileLink SoC) and boot firmware by hand.
Recommendation: A for first Linux boot (least integration risk), with B kept as the fallback. A reuses none of the AMD DDR4 bring-up
RTL except the pin/bank knowledge and test design; the AMD IP stays the vendor-supported alternative if USPDDRPHY calibration fails.

## Evidence
README.md/LICENSE of each repo (GitHub, read 2026-10-18); LiteX `cpu/*/core.py` variants; Buildroot mailing-list history for RV32 glibc;
LiteDRAM `usddrphy.py` header; Tampere thesis for CVA6 CoreMark (third party, single data point).
