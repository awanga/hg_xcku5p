# 0007 — Scope of the CPU benchmark and interconnect tuning for the MVP

- Status: accepted for the MVP by the agent on 2026-11-13, **owner to confirm** (it closes two Phase 7 tasks)
- Date: 2026-11-13

## CPU candidates
- VexiiRiscv RV64IMA is measured in simulation and on the board (docs/validation/cpu-benchmarks.md, l2-study.md, linux-bringup.md): CoreMark-style and Linux workloads, resources at 333 MHz, timing closure.
- VexRiscv-SMP has synthesis numbers only (docs/validation/cpu-ooc-synthesis.md). It is RV32 only, so it cannot run the RV64 userland and kernel this project targets (decision 0001, user preference for 64-bit),
  and a like-for-like Linux benchmark would need a second toolchain, kernel, rootfs and SoC. It stays a synthesis-only baseline; no further measurement is planned for the MVP.
- CVA6 was dropped in 0001. Final CPU: VexiiRiscv RV64IMA with the coherent hub and a 128 KiB L2 (0006).

## Interconnect widths and arbitration
- Memory path: the CPU's AXI port is 256 bits, equal to the DDR4 controller user interface (32-bit bus, burst 8), on one 333.33 MHz clock with no crossing. A narrower port loses bandwidth, a wider one has no
  matching DDR width; there is no second value to compare.
- Peripheral path: AXI4-Lite, 32 bits, crossed once to 100 MHz (cc_per) into one crossbar; every peripheral IP is a 32-bit AXI-Lite slave. A single CPU master and one DMA read master (eth_dma) mean arbitration
  is the crossbar's default; the measured limit of the Ethernet window is the LiteEth bridge latency (190 ns per access), not the crossbar.
- DMA: one write path (eth_dma) and, with the HDMI scan-out, one read path into the hub's single 64-bit DMA port; the hub arbitrates with the CPU.
- Measured one variable at a time: CPU clock, L1/L2 sizes, DDR4 rate (l2-study.md, ddr4-bringup.md, 0006). Not explored because no alternative exists or the evidence would not change the design: memory port width,
  crossbar arbitration scheme.
- Revisit when a second high-bandwidth master (PCIe, QSFP) is added.
