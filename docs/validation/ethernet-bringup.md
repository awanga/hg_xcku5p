# Ethernet bring-up (GMII, LiteEth)

Bitstream build/soc/vv_eth5 (source f8d2f4f), SD-booted Linux 6.18.59, router with DHCP. Physical-board evidence.

## Result
- Link 1000 Mb/s, DHCP lease obtained at boot, ping 0.35-0.45 ms.
- Receive throughput (2026-11-06): busybox `wget` of a 40 MB file from a host Python http.server, three runs, each exactly 40000000 bytes in 13.1 s =
  3.05 MB/s (24 Mb/s). Likely CPU/bus bound (333 MHz in-order core, packet buffers behind the 100 MHz AXI-Lite peripheral path); not profiled.
- Transmit throughput not measured: busybox has no nc/iperf, and `wget --post-file` hung against the test server. Add iperf3 to the rootfs.
- /proc/interrupts: uartlite, spi and eth0 all count.
- An earlier no-link period was a bad cable (RJ45 LEDs stayed dark; a known-good cable fixed it); not an RTL fault.

## Design facts established
- LiteEthPHYGMII derives GTX_CLK and the TX domain from the PHY RX clock. The RTL8211EG only outputs 125 MHz RXCLK once linked
  (idle RXCLK is 2.5 MHz), so the generated core is post-processed to use a 125 MHz MMCM clock (fpga/scripts/gen_liteeth.sh).
- The core's CSR/buffer map lies outside the CPU's 64 KiB peripheral window; eth_addr_map.v remaps it at 0xF8008000 (32 KiB).
- The generated MDIO IOBUF has no pin and is removed; PHY RSTB is held ~21 ms by soc_top.
- Board registers 0x18 (PHY RSTB state) and 0x1C (RXCLK edge count per 2^15 per_clk cycles: 40960 = 125 MHz) aid bring-up.
- LiteEth releases <= 2024.12 / tag 2026.08 never flag CRC errors on the 8-bit GMII path; upstream master is pinned (docs/versions.md).

## Not validated / open
- GMII input/output delay constraints are datasheet-based (unverified); WNS of vv_eth5 is +0.003 ns.
- Serial console intermittently drops or stops output on several bitstreams, including pre-Ethernet ones (TASKS.md Open).
- Transmit throughput, CPU load, error counters and long-run stability untested.
