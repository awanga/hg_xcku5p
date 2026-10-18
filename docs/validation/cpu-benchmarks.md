# VexiiRiscv benchmarks (RTL simulation, 2026-10-18)

Evidence class: **RTL simulation** (SpinalSim/Verilator, `vexiiriscv.tester.TestBench`, no RVLS co-simulation) with a fixed-latency,
unlimited-bandwidth memory model (`--memory-latency N` core clocks on both buses). Not board data; the real DDR4 controller adds
queuing, refresh stalls and a limited clock ratio. VexRiscv-SMP was **not** simulated (only synthesised, see 0001).

Toolchain: xPack GCC 15.2.0-1 (riscv-none-elf, sha256 aaaa8060...3758), JDK 21.0.12 (Temurin; needed for jni.h), Verilator 5.032,
VexiiRiscv `dev` 0dc189e + SpinalHDL 58837d3 (checkouts under `build/third_party`, not committed). Build ELFs with `tests/bench/build_elfs.sh`,
run sweeps from `fpga/scripts/cpu/sweeps/`. All runs: RV64IMA, S+U mode, MMU, 64-bit cache memory width, `--with-lsu-bypass`, 1 lane.

## CoreMark (10 iterations, CRC validated, -O2, rv64ima, latency 20 unless noted)
| I$/D$ | predictor | prefetch | CoreMark/MHz |
|---|---|---|---|
| 4K/4K 1-way | none | no | 2.31 (lat 20), 2.21 (lat 40) |
| 8K/8K 2-way | none | no | 2.43, 2.41 |
| 16K/16K 4-way | none | no | 2.45, 2.45 |
| 8K/8K 2-way | BTB+RAS+gshare | no | 3.17, 3.14 |
| 8K/8K 2-way | BTB+RAS+gshare | yes | 3.19 |
| 16K/16K 4-way | BTB+RAS+gshare | no | 3.21, 3.20 |
| 32K/32K 8-way | BTB+RAS+gshare | no | 3.21 |
| (RV32IMA 8K/8K 2-way) | BTB+RAS+gshare | no | 3.21, 3.16 |
CoreMark's working set fits in 8 KB, so it measures the pipeline, not the memory system: **the branch predictor is worth +30 %**
(about 2 BRAM tiles and 300 LUT); cache size and memory latency barely move CoreMark. RV64 costs nothing in CoreMark/MHz versus RV32.
Vexii's own comments quote 3.2-3.7 CoreMark/MHz for these (1-lane) configurations; the 5.24 headline is a dual-issue max-IPC build.

## Working-set sweep (`tests/bench/membench.c`), latency 20 / 40
Cells are cycles per 64-byte line (sequential read, copy) or per dependent load (chase). Source of truth: `build/bench/m64_*.log`.
| Config (RV64, predictor on unless noted) | seq 16K ws, lat20 | seq 256K ws, lat20 | chase 256K, lat20 | copy 256K, lat20 | seq 256K, lat40 |
|---|---|---|---|---|---|
| 4K/4K 1-way, no predictor | 58 | 58 | 45 | **648** | 78 |
| 8K/8K 2-way | 53 | 53 | 40 | 111 | 73 |
| 8K/8K 2-way + prefetch | 29 | 28 | 40 | 68 | 44 |
| 16K/16K 4-way | 18 (hit) | 53 | 40 | 111 | 73 |
| 16K/16K 4-way + prefetch | 19 (hit) | 28 | 40 | 70 | 44 |
| 32K/32K 8-way | 18 (hit) | 53 | 40 | 111 | 73 |
Findings:
1. The L1 behaves as a cliff at its capacity (hit ~18 cycles/line, miss 53 at latency 20, 73 at latency 40): the CPU is **latency-bound**, not
   DDR-bandwidth-bound. Sequential misses move 64 B per 53 cycles (about 1.2 B/cycle), roughly 6 % of the 32-bit DDR4-1600 peak at 200 MHz.
2. Hardware prefetch (`--fetch-l1-hardware-prefetch=nl --lsu-hardware-prefetch=rpt`, refill count 2) cuts sequential/copy miss cost by 45-55 %
   (53 -> 28 cycles/line; copy 111 -> 68) at +~700 LUT/+~600 FF and **no BRAM**. It does nothing for random dependent loads (chase unchanged).
3. A direct-mapped 4K cache thrashes on the copy test (a and b alias): 648 cycles/line. Use at least 2-way.
4. The store-buffer option (`--lsu-l1-store-buffer-slots=2 --...-ops=32`) gave no measurable change on this test (109 vs 111); not adopted.
5. L1 size is capped by the MMU: Vexii asserts "MMU require not more than 64 sets", i.e. ways x 4 KB (32 KB at 8-way). Larger capacity needs an L2.

## Resource cost (out-of-context synthesis, same arguments; see decisions/0001)
| Config | LUT | FF | BRAM tiles (of 480) |
|---|---|---|---|
| 8K/8K 2-way + predictor | 5806 | 4445 | 12 |
| 8K/8K 2-way + predictor + prefetch | 6494 | 5047 | 12 |
| 16K/16K 4-way + predictor | 6359 | 4805 | 22 |
| 16K/16K 4-way + predictor + prefetch | 6953 | 5409 | 22 |
| 32K/32K 8-way + predictor | 7060 | 5524 | 42 (8.8 %) |

Limitations: synthetic test and CoreMark only (no Linux/real workload); fixed-latency memory; 10 CoreMark iterations (below the
10-second official rule; the per-MHz figure is cycle-exact for the iterations run); one seed; no frequency data (post-route Fmax pending).

## Out-of-context place-and-route Fmax (Vivado 2026.1, 2026-10-18)
VexiiRiscv RV64, 16K/16K 4-way, BTB+RAS+gshare, prefetch (`v64_16k4w_pf`), native cache buses (no AXI adapters, no SoC fabric).
`opt_design; place_design; phys_opt_design; route_design; phys_opt_design`, default directives, one run each, clock 1 port.
| Target clock | Port I/O delay | WNS (ns) | WHS (ns) | Estimated Fmax = 1/(T-WNS) |
|---|---|---|---|---|
| 5.00 ns (200 MHz) | none (reg-to-reg) | +0.614 | +0.037 | 228 MHz |
| 4.00 ns (250 MHz) | none | +0.274 | +0.031 | 268 MHz |
| 3.33 ns (300 MHz) | none | +0.091 | +0.030 | 309 MHz |
| 5.00 ns | 40 % of period in/out | +0.322 | +0.019 | 214 MHz |
| 4.00 ns | 40 % of period in/out | +0.259 | +0.041 | 267 MHz |
All five runs met timing (the tool stops optimising once met, so the real limit is above the highest target tried, about 300 MHz).
Caveats: out of context (ideal clock tree, no neighbouring logic, no congestion from DDR4/AXI/peripherals); the estimate says the core
itself is not the limit. The SoC clock will be set by the AXI/interconnect, the DDR4 controller clock relationship (ui_clk 200 MHz at DDR4-1600)
and cache-bus-to-AXI adapters; 150-200 MHz is the realistic planning range until a SoC is placed.
