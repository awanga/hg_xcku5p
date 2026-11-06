# Ethernet bring-up (GMII, LiteEth)

Bitstream build/soc/vv_eth5 (source f8d2f4f), SD-booted Linux 6.18.59, router with DHCP. Physical-board evidence.

## Result
- Link 1000 Mb/s, DHCP lease obtained at boot, ping 0.35-0.45 ms.
- Receive throughput (2026-11-06): busybox `wget` of a 40 MB file from a host Python http.server, three runs, each exactly 40000000 bytes in 13.1 s =
  3.05 MB/s (24 Mb/s). Likely CPU/bus bound (333 MHz in-order core, packet buffers behind the 100 MHz AXI-Lite peripheral path); not profiled.
- iperf3 (2026-11-06, board 192.168.1.247 to host, 10 s TCP, vv_sync1, 1 CPU, 1000 Mb/s link; CPU split from /proc/stat):
  | Direction | Throughput | Retransmits | CPU |
  | board to host (TX) | 70 Mb/s (two runs: 70.6, 69.8) | 0 | sys 94 %, idle 0 % |
  | host to board (RX, -R) | 43.5 Mb/s (two runs: 43.7, 43.5) | ~3100 | sys 21 %, softirq 67 %, idle 12 % |
  The MAC's own drop counter (`ethmac_sram_writer_errors`, CPU address 0xF8009008) rose by ~4050-4270 per 10 s RX run, equal to the TCP retransmits;
  CRC and preamble error counters (0xF8009040, 0xF800903C) stayed 0. So the loss is both RX slots (2 x 2 KiB) being full when a frame arrives:
  the CPU takes ~285 us per received packet and a 1 Gb/s sender delivers one every 12 us. /proc/net/dev and `ethtool -S` do not show it.
  Capping the sender (`-b 40M/55M/70M`) changed nothing (39-40 Mb/s, same drops): iperf3's `-b` does not pace TCP here. A paced sender was not tested.
  UDP receive at 30 Mb/s (1400 B datagrams) lost 0 of 21434 datagrams.
- Cause of the low rate: packet data is copied by the CPU through the buffer window with `memcpy_fromio/toio`. A 32-bit access to that window takes
  ~190 ns (read 193, write 184; user-space mmap of /dev/mem, 500 x 2 KiB), 20-22 MB/s at best, against 11 ns for DDR. A 1500-byte frame costs ~70 us
  of CPU for the copy alone (memcpy_fromio already uses 64-bit accesses; a 64-bit read costs 346 ns, a byte read 194 ns, so wider accesses do not help).
  The copy is only ~25 % of the RX per-packet cost (~285 us) and ~40 % of TX (~171 us); the rest is the network stack: TCP loopback on the board
  reaches 660 Mb/s with large segments, but UDP loopback with 1400 B datagrams only 43.8 Mb/s (~3.9k packets/s, both ends on one CPU).
- /proc/interrupts: uartlite, spi and eth0 all count.
- An earlier no-link period was a bad cable (RJ45 LEDs stayed dark; a known-good cable fixed it); not an RTL fault.

## Where the RX time goes (kernel profile, 2026-11-06)
Profiling kernel (`KPROFILE=1 DTS_NAME=hg-xcku5p-sdroot-prof linux/build_sd.sh`, `profile=2`, `readprofile` with the kernel System.map), iperf3 RX, 10 s,
2488 samples, 37.7 Mb/s:
- handle_softirqs 738 (30 %): the sampling tick cannot fire while the Ethernet interrupt handler runs with interrupts off, so this is that handler
  (frame copy `memcpy_fromio` and CSR accesses) charged to the first instruction after interrupts are re-enabled. Consistent with the ~25 % copy estimate.
- idle 266 (11 %). liteeth_start_xmit + memcpy_toio (ACK transmit) ~100 (4 %).
- The remaining ~55 % is spread over the TCP/IP stack and allocator with no function above 2 % (tcp_recvmsg, ip_rcv, __alloc_skb, page and slab alloc/free,
  checksum, scheduler): no cheap software hotspot to remove.
- More RX slots were considered and not built: LiteX requires power-of-two slot regions, so the 16 KiB buffer window allows only 4 RX + 2 TX; 2 more slots
  absorb ~50 us of a burst against ~285 us per packet, so they cannot change the sustained rate.

## Design facts established
- LiteEthPHYGMII derives GTX_CLK and the TX domain from the PHY RX clock. The RTL8211EG only outputs 125 MHz RXCLK once linked
  (idle RXCLK is 2.5 MHz), so the generated core is post-processed to use a 125 MHz MMCM clock (fpga/scripts/gen_liteeth.sh).
- The core's CSR/buffer map lies outside the CPU's 64 KiB peripheral window; eth_addr_map.v remaps it at 0xF8008000 (32 KiB).
- The generated MDIO IOBUF has no pin and is removed; PHY RSTB is held ~21 ms by soc_top.
- Board registers 0x18 (PHY RSTB state) and 0x1C (RXCLK edge count per 2^15 per_clk cycles: 40960 = 125 MHz) aid bring-up.
- LiteEth releases <= 2024.12 / tag 2026.08 never flag CRC errors on the 8-bit GMII path; upstream master is pinned (docs/versions.md).

## Interrupt synchronization (found during this bring-up)
- report_cdc showed the UART, SPI and Ethernet interrupts (per_clk) feeding the PLIC gateways (CPU clock) with no synchronizer. Each gateway samples
  its source in two flops; if they disagree the gateway waits for a completion that never comes and the interrupt is dead. Symptoms: SD detection
  hanging at boot, serial input dying. Placement-dependent: identical source gave 0/16 hangs (vv_eth5) and 9/16 (vv_base2).
- Fix: fpga/rtl/irq_sync.v (2-flop, ASYNC_REG). Board evidence, vv_sync1: 16/16 boots detect the card and reach login; typed-burst test 50/50.

## Not validated / open
- GMII input/output delay constraints are datasheet-based (unverified); WNS of vv_eth5 is +0.003 ns.
- Long-run stability untested. RX loss source unconfirmed. Possible fixes (not tried): more RX slots (only removes retransmits), offloading the buffer copy to a DMA master (none exists yet).
