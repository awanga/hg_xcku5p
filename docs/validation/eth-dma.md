# Ethernet receive copy engine (eth_dma)

Evidence: **simulation** (tests/rtl/tb_eth_dma.v, 6 mutants) and **board** (bitstream `build/soc/vv_dma3`, 2026-11-13).

- Engine: `fpga/rtl/eth_dma.v` on per_clk, crossbar slave 10 at 0xF800E000 plus a second crossbar master that reads the LiteEth buffer window; its single-beat 64-bit writes cross to the CPU clock
  through `cc_dma` into the coherent hub DMA port (no cache maintenance). PLIC source 8. The LiteEth window is split (CSR/MDIO 0xF8008000, 16 KiB; buffers 0xF800C000, 8 KiB) so the engine fits in the
  CPU's 64 KiB peripheral region. Driver: `linux/patches/0001-net-liteeth-optional-receive-copy-engine.patch` (device tree "dma" reg and interrupt).
- Build: Performance_ExplorePostRoutePhysOpt, WNS +0.001 ns, WHS +0.011 ns, 24.7k LUT (+1.1k versus vv_io2). The first two builds missed by 0.085 and 0.026 ns on CPU-internal paths (post-route fix reached +0.001 on vv_dma2f).
- Bug found on the board: `irq_sync_q` was 7 bits wide, so source 8 never reached the PLIC (DONE set, IEN set, PLIC pending 0). Fixed to 8 bits in vv_dma3. Nothing in simulation covers soc_top wiring.
- Result: smoke 19/19 (`--sd --net`) from JTAG and again after `-r` from the flash. iperf3 10 s, board <- host (RX): **46.2 Mb/s** (baseline 41.3 on the L2 image without the engine, +12 %), 2735 retransmissions
  (3362 before), 71.7k frames through the engine, rx_errors 0, rx_dropped 0. TX unchanged at 71 Mb/s. Below the +15-25 Mb/s estimate: the source read still goes through the ~190 ns/word LiteEth bridge, so the
  engine mainly removes the CPU from the copy, not the copy time; the remaining cost is the network stack and one extra interrupt per frame.
- Not done: a burst-capable buffer path (dual-port buffer read at 32/64 bits) would remove the bridge limit; packet-loss under longer runs; the engine is tested only with 1500-byte TCP and ARP/ICMP frames on the board.
