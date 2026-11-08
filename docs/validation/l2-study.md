# UltraRAM L2 cache study (VexiiRiscv SoC)

Status 2026-10-29. Simulation (Verilator, generated netlists) and out-of-context implementation only; no L2 variant has run on the board.

## Method
- Netlists: `fpga/scripts/cpu/gen_soc.sh` (`--with-dma --l2-bytes N --l2-ways W`; the L2 needs the coherent fabric, so the baseline for L2 variants is `soc_dma`, CPU + coherency hub + DMA port, no L2). The L2 data array is generated as a blackbox (`VEXII_L2_BLACKBOX=1`, `fpga/patches/vexii-l2-blackbox.patch`) and mapped to URAM with `fpga/scripts/cpu/uram_l2.sh`. Without that, Vivado puts it in BRAM (512 KiB: 144.5 BRAM tiles, 0 URAM); the symbol-split form of the array forced into URAM used all 64 URAM.
- Performance: `fw/membench` on the netlist (`tests/soc/tb_soc.v`), memory model read latency 80 cycles, one 256-bit beat per 2 cycles (400 MHz core over 200 MHz DDR4 user clock). Values are core cycles x100 per 64 B line (seq, copy) or per access (chase). 4 MiB points did not finish in the simulation limit and are omitted.
- Resources/timing: `fpga/scripts/cpu/ooc_soc.sh <name> 2.5` (out-of-context, 400 MHz target, no port constraints).

## Results
| Variant | LUT | FF | BRAM | URAM | WNS @2.5 ns (est. Fmax) |
|---|---|---|---|---|---|
| soc_base (no coherency) | 8559 | 9345 | 10 | 0 | -0.43 (~340 MHz) |
| soc_dma (hub + DMA port, no L2) | 10444 | 12116 | 10 | 0 | -0.44 (~340 MHz) |
| L2 128 KiB 4-way | 11934 | 14284 | 12 | 4 | -0.47 (~335 MHz) |
| L2 256 KiB 4-way | 12034 | 14293 | 14 | 8 | -0.63 (~320 MHz) |
| L2 512 KiB 4-way | 11982 | 14415 | 16.5 | 16 | -0.90 (~295 MHz) |
| L2 1 MiB 4-way | 12042 | 14442 | 18.5 | 32 | -1.21 (~270 MHz) |

| Working set | soc_dma seq/chase/copy | L2 256K | L2 512K | L2 1M (4w) |
|---|---|---|---|---|
| 64 KiB | 90 / 111 / 210 | 41 / 27 / 117 | 43 / 29 / 120 | 43 / 29 / 120 |
| 256 KiB | 90 / 114 / 212 | 41 / 28 / 241 | 43 / 30 / 120 | 43 / 30 / 120 |
| 512 KiB | 90 / 114 / 212 | 127 / 106 / 253 | 43 / 30 / 241 | 43 / 30 / 109 |
| 1 MiB | 85 / 114 / 212 | 127 / 111 / 255 | 127 / 99 / 249 | 43 / 30 / 226 |
| 2 MiB | 85 / 114 / 212 | 127 / 113 / 257 | 127 / 110 / 255 | 127 / 99 / 249 |

(The 8-way 1 MiB L2 behaves like the 4-way one within 15 % on these tests; 128 KiB is like 256 KiB shifted one size down.)

## Findings
- An L2 that holds the working set: ~2.1x on sequential reads, ~3.8x on dependent random loads, ~1.8x on copy. The gain is large only when the set is between the L1 (16 KiB) and the L2 size.
- When the set exceeds the L2, sequential read is ~40 % slower than without L2 (127 vs 90) and chase/copy are unchanged or worse: the L2 adds miss latency.
- LUT cost is a constant ~1.5k over the coherent baseline, independent of size; the coherency hub/DMA port itself costs ~1.9k LUT. URAM cost is linear: 4 / 8 / 16 / 32 for 128 / 256 / 512 / 1024 KiB.
- Fmax falls with L2 size (about -15 MHz per doubling of capacity) from the URAM cascade read path.
- URAM left for peripherals: 60 / 56 / 48 / 32 of 64.

## Provisional recommendation
256 KiB 4-way (8 URAM, 12.5 % of the device, 56 left; ~20 MHz of Fmax). 128 KiB is nearly free in Fmax but covers few working sets; 512 KiB pays 16 URAM and ~45 MHz for a larger set. The tests are synthetic; the deciding data is a Linux-like workload (kernel build, compression, database) once Linux runs; revisit then. The coherent fabric is needed anyway for PCIe/Ethernet DMA, so the hub cost is not attributable to the L2.

## Board measurements (2026-10-29, CPU and DDR4 ui_clk 333.33 MHz, DDR4-2667)
Same membench, loaded over the UART (`tools/load.py fw/membench/build/membench_app.bin`); cycles x100 per 64 B line (seq, copy) / per access (chase).
Timing of the L2 images: 256 KiB WNS -0.071 ns, 512 KiB WNS -0.271 ns (not met; they ran correctly in minutes at room temperature, treat
the numbers as performance data only). soc_base (no coherency, no L2) met timing.

| Working set | no L2 (soc_base) | L2 256 KiB | L2 512 KiB |
|---|---|---|---|
| 16 KiB (L1) | 20 / 7 / 88 | 20 / 7 / 91 | 20 / 7 / 92 |
| 64 KiB | 32 / 50 / 94 | 41 / 27 / 95 | 43 / 29 / 97 |
| 256 KiB | 31 / 54 / 95 | 41 / 28 / 147 | 43 / 30 / 98 |
| 512 KiB | 31 / 55 / 95 | 67 / 59 / 151 | 43 / 30 / 147 |
| 1 MiB | 31 / 55 / 95 | 67 / 61 / 152 | 67 / 56 / 149 |
| 4 MiB | 31 / 55 / 95 | 67 / 62 / 153 | 67 / 62 / 153 |

(seq / chase / copy; soc_base row from the 4 MiB-capable run, values for 64 KiB..4 MiB steady within 3 %.)

Findings on hardware (these supersede the simulation conclusions where they differ):
- The real DDR4 path is much faster than the simulation model: uncached sequential read 31 cycles/line, random read 55 cycles/access (~165 ns), thanks to the L1 hardware prefetcher.
- An L2 that holds the working set helps random access only (chase 55 -> 28-30, 1.9x). Sequential read gets slower (31 -> 41-43, 1.4x worse) and copy does not improve.
- A working set larger than the L2 costs 2x on sequential read (31 -> 67), 1.6x on copy and ~10 % on random access.
- So an L2 is not a clear win for this core with this memory: it pays only for random access over 64 KiB..L2-size sets. The comparison that matters for the decision is hub-only coherency (soc_dma) against the L2 variants, since coherency is needed for DMA anyway; that baseline has not been measured on the board yet.

### Hub-only coherency baseline and 128 KiB L2 (board, same conditions)
`soc_dma` (coherency hub + DMA port, no L2; WNS -0.061 ns, ran correctly) and the 128 KiB L2 (WNS +0.011 ns):

| Working set | soc_base | soc_dma (hub) | L2 128 KiB |
|---|---|---|---|
| 64 KiB | 32 / 50 / 94 | 40 / 57 / 103 | 41 / 27 / 96 |
| 256 KiB | 31 / 54 / 95 | 40 / 61 / 101 | 67 / 58 / 126 |
| 4 MiB | 31 / 55 / 95 | 40 / 62 / 101 | 67 / 62 / 115 |

- The coherency hub alone costs ~29 % on sequential read and ~12 % on random access versus the non-coherent SoC (and ~1.9k LUT).
- Against the hub baseline an L2 that holds the set: random access 2.1x faster, sequential and copy unchanged; when the set exceeds the L2: sequential 1.7x slower, copy ~1.5x slower, random unchanged.

### Revised recommendation (supersedes "provisional recommendation" above)
Do not add an L2 yet. Start with the hub-only coherent SoC (needed for DMA) and decide on an L2 with a Linux workload: it helps only random access
over sets between the L1 and the L2 size, and penalises everything larger. If random-access sets of 64-256 KiB dominate, 128-256 KiB (4-8 URAM) is the size to try;
512 KiB and above give no board-measured benefit that justifies the extra Fmax loss (its image misses 333 MHz timing).

## Linux workload baseline (2026-11-06, soc_base vv_sync1, no L2, no coherency hub)
Measured under Linux (3,000,000 bytes of concatenated rootfs binaries, tmpfs, busybox tools, idle system; `time`):
| Workload | Time | Cycles/byte at 333 MHz |
| gzip -c (default level) | 13.05 s | ~1450 |
| gunzip | 0.98 s | ~109 |
| md5sum | 0.18 s | ~20 |
- gzip's hash chains and 32 KiB window are random access over a set above the 16 KiB L1: the class an L2 helps. md5sum and gunzip are mostly
  sequential/compute: an L2 would not help them (and the study shows it can slow them).
- Ethernet is not an L2 argument: packet copy is bound by MMIO latency (~190 ns per 32-bit access), which no cache covers.
- Not decided: there is no Linux-capable L2 image, so the benefit on gzip is unmeasured. Upper bound from the study (random access up to ~2x on a
  set that fits) would turn 13 s into at most ~7 s for that workload only, at ~15-20 MHz of Fmax. The L2 variants lack the SD/Ethernet SoC and miss timing.
- User-space rdcycle/rdinstret trap (illegal instruction): no CPI measurement from user space.

## Linux workload with an L2 (2026-11-08, full SoC: SD, Ethernet, peripherals)
Same CPU, DDR4 and rootfs; only the SoC netlist differs. Images: `vv_d8g1` (no hub, no L2; the baseline), `vv_l2e256` (coherency hub + 256 KiB 4-way L2),
`vv_l2e128` (hub + 128 KiB 4-way L2). Workload (`time`, busybox, input = first 3,000,000 bytes of `/usr/bin/* /usr/lib/*.so* /bin/busybox` in tmpfs, two runs each,
runs within 1 %): gzip -c, gunzip -c, md5sum, a 20000-iteration shell loop, `tar cf - /usr /lib /bin /sbin | wc -c` (second run, warm), `sort` of the input.

| Workload | no L2 | L2 256 KiB | L2 128 KiB |
|---|---|---|---|
| gzip -c (3 MB) | 13.5 s | 8.5 s (1.58x) | 8.7 s (1.55x) |
| gunzip | 1.00 s | 0.93 s | 0.94 s |
| md5sum | 0.18 s | 0.18 s | 0.18 s |
| shell loop | 2.8 s | 2.1 s (1.33x) | 2.2 s (1.28x) |
| tar | 0.54 s | 0.48 s | 0.50 s |
| sort | 24.4 s | 23.1 s (1.06x) | 23.3 s (1.05x) |
| Timing (333 MHz) | WNS +0.012 (vv_fan2) / +0.003 (d8g1) | WNS -0.154 (fix pass did not close it; run as is, performance data only) | WNS +0.020, WHS +0.010 |
| CLB LUT / FF / BRAM / URAM | 20.5k / 24.8k / 42.5 / 0 | not extracted | 22.7k / 28.0k / 44.5 / 4 |

Findings:
- Both L2 images boot Linux from SD, run the workloads and reply to ping; Ethernet throughput and the other peripherals were not re-measured on them.
- The gain comes from random-access user code (gzip's hash chains, interpreter state): 1.3-1.6x. Sequential and compute-bound jobs (gunzip, md5sum, tar) do not change, and the
  hub's sequential-read penalty seen with membench (about 29 %) does not show up in these workloads. The 128 KiB L2 gets 97 % of the 256 KiB gain here and meets timing; 256 KiB does not (-0.154 ns).
- Cost of the 128 KiB option versus the non-coherent SoC: +2.2k LUT, +3.2k FF, +2 BRAM tiles, 4 URAM (6 % of the device), and the coherency hub that DMA needs anyway.
- Caveats: one busybox workload set, one run per image on the board, a single input file; the comparison includes the hub (no hub-only Linux image was measured).

Recommendation: adopt the coherent SoC with a 128 KiB 4-way L2 as the default. 256 KiB buys nothing measurable here and misses timing; no L2 leaves 1.3-1.6x on the table for
random-access code. This needs the owner's confirmation (it changes the default netlist, the flash image and the ROM/boot images are unchanged).

