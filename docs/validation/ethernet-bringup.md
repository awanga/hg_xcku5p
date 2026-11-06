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
  `ethtool -S` is not implemented by the driver; /proc/net/dev shows no rx/tx errors or drops, so the RX retransmits are loss the driver cannot see
  (LiteEth has 2 RX slots of 2 KiB; a frame arriving while both are held is dropped in hardware). Not yet confirmed as the cause.
- Cause of the low rate: packet data is copied by the CPU through the buffer window with `memcpy_fromio/toio`. A 32-bit access to that window takes
  ~190 ns (read 193, write 184; user-space mmap of /dev/mem, 500 x 2 KiB), 20-22 MB/s at best, against 11 ns for DDR. A 1500-byte frame costs ~70 us
  of CPU for the copy alone. The path is bound by MMIO latency (333 MHz CPU, clock converters, 100 MHz AXI-Lite peripheral bus), not DDR or cache.
- /proc/interrupts: uartlite, spi and eth0 all count.
- An earlier no-link period was a bad cable (RJ45 LEDs stayed dark; a known-good cable fixed it); not an RTL fault.

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
- Long-run stability untested. RX loss source unconfirmed. Possible fixes (not tried): 64-bit buffer accesses, more RX slots, DMA through the coherent port.
