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
