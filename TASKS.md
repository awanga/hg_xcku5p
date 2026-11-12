# Development Plan and Progress

## Current status (<=100 lines; history in HISTORY.md)

- Decision: CPU study is VexRiscv/VexiiRiscv vs CVA6 (MicroBlaze V and Rocket Chip dropped, 2026-10-18).
  Reason: user direction. Status: README/AGENTS/TASKS updated; decision record 0001 started.
- Decision: no self-hosted CI runner; Vivado + hardware jobs run locally; hosted GitHub Actions only for non-licensed checks.
  Reason: user direction. Status: README/AGENTS/TASKS updated.
- Decision: default SoC = coherency hub + 128 KiB 4-way L2 in UltraRAM (soc_l2u_128k_w4, fpga/scripts/cpu/gen_default_soc.sh), owner-approved 2026-11-08.
  Reason: gzip 1.55x, shell 1.28x under Linux, timing met. Status: docs/decisions/0006-l2-cache.md; vv_l2e128 (WNS +0.020, WHS +0.010) is the reference bitstream and is in the config flash (verified, cold power-up boots).
- Decision: board memory/flash (owner-stated, NOT yet schematic-verified): config flash MT25QU256ABA1EW9-0SIT;
  DDR4 2 x MT40A256M16GE-075E, 32-bit bus (1 GiB). Status: recorded in docs/hardware/board-inventory.md.
- Status: Vivado 2026.1 works for xcku5p-ffvb676-2-i with the free license (scripts/check-env.sh PASS: synth, place, route, bitstream
  on a trivial design; simulation/board evidence: none). Catalog has ddr4, xdma, axi_ethernet, tri_mode_ethernet_mac,
  axi_quad_spi, axi_uartlite, axi_gpio, axi_iic, microblaze_riscv; no axi_sdc (use another SD controller). Whether
  axi_ethernet/TEMAC need a paid license for bitstream generation is untested.
- Decision: MIT license (docs/licensing.md); deps checked, no conflict. Schematic PDF kept local (gitignored).
- Status: schematic reviewed (docs/hardware/board-inventory.md); user clocks/UART pins confirmed. Findings to resolve:
  JTAG is FT232H (not hub-attached EEPROM; EEPROM is on FT232H); ETH mode GMII vs RGMII strap unclear; MDC/MDIO, INT not
  wired to FPGA; HDMI DDC not wired to FPGA; SD has no CD/WP/UHS; VADJ jumper must be 1.8 V for UART; FT232H 3.3 V -> bank0 1.8 V JTAG check.
- Status: owner confirmed LED, key, MS5611 and PCIe x4 pinouts (2026-10-18); PCIe PERST# 3.3 V into bank 66 (VADJ) flagged.
- Decision: Ethernet runs GMII (board default); RGMII optional via R158 rework (0003-ethernet-gmii.md).
- Status: CPU study (decisions/0001): VexiiRiscv RV32 4.4k LUT, VexRiscv SMP 5.8k, CVA6 RV32 20.6k (synthesis only, no
  CoreMark yet). CVA6 dropped (user, 2026-10-18).
- Decision (2026-10-18): finalists VexiiRiscv + VexRiscv-SMP; prefer 64-bit but minimise BRAM; LiteEth accepted; AMD DDR4 IP
  preferred with LiteDRAM USPDDRPHY kept as alternative pending hardware speed. README updated (needs approval before commit).
- Status: VexiiRiscv benchmarks (RTL sim): CoreMark 3.2/MHz with predictor (+30 %), prefetch halves seq-miss cost at 0 BRAM,
  32K cache needs 42 BRAM. Interim pick: RV64, 16K/16K 4-way + BTB/RAS/gshare + prefetch (22 BRAM). See validation/cpu-benchmarks.md.
- Status: core-only OOC place-and-route Fmax: timing met at 300 MHz target (WNS +0.09 ns); SoC clock will be set by fabric/DDR4, plan 150-200 MHz.
- Future (user request): UltraRAM L2 sweet-spot study incl. URAM left for peripherals (decisions/0001, end).
- Status (2026-10-29, board connected via openFPGALoader --cable ft232, console /dev/ttyUSB2): DDR4 bring-up verified on hardware at
  DDR4-1600, 2000 and 2667 (tCK 750, ui_clk 333.33 MHz measured): calibrated, 0 errors; AXI-port write/read ~8.6/4.6 GB/s at 2667.
  See validation/ddr4-bringup.md (needs update) and soc-minimal.md.
- Status: minimal SoC (Vexii RV64 + AMD DDR4 + boot ROM + UART) boots on the board at 400 MHz CPU / DDR4-1600, 16 MiB tests 0 errors;
  static timing NOT met (-0.55 ns, BTB->fetch L1 BRAM path); core-only realistic Fmax ~340 MHz.
- Status: L2 study measured on the board (validation/l2-study.md): L2 helps only random access over L1..L2-size sets (2x), penalises sequential/larger sets; recommendation: no L2 yet, hub-only coherent SoC, revisit with a Linux workload. Coherency hub costs ~29 % seq / 12 % random vs non-coherent. 1 MiB L2 not built.
- Decision (user, 2026-10-29): CPU and DDR4 share one clock (ui_clk, 333.33 MHz at DDR4-2667). Status: SoC bitstream (build/soc/vv_333)
  met timing (WNS +0.006, ExplorePostRoutePhysOpt) and ran on the board: 0 errors, CPU stream write/read 350/516 MB/s. UART loader
  (fw/boot, tools/load.py, 921600 baud) passes simulation; bitstream build/soc/vv_333b with the loader was started and NOT yet loaded on the board.
- Status (2026-10-30): Linux 6.18.59 + OpenSBI 1.9 + Buildroot boots to a login prompt on the board (validation/linux-bringup.md), now also cold from the SD
  card (ROM -> OpenSBI -> kernel, read-only ext4 root on p1, journalled noatime /data on p2, root home persists across reset; resets during the ROM
  read and during Linux boot recover). vv_sd2 misses timing by 0.065 ns (ran). Next: Ethernet (LiteEth GMII), L2 decision with a Linux workload, timing margin.
- Status (2026-11-06): Ethernet merged (GMII 1000 Mb/s, DHCP, ping 0.4 ms, RX 3.05 MB/s; docs/validation/ethernet-bringup.md). The intermittent SD-detection
  hang and dead-console symptoms had one root cause: the UART/SPI/Ethernet interrupts crossed per_clk -> CPU clock with no synchronizer into the PLIC
  gateway's two sampling flops (pending, wait-for-completion), which can disagree and block an interrupt for good; it depends on placement (same source:
  vv_eth5 0/16 hangs, vv_base2 9/16). Fixed with irq_sync (2 flops); vv_sync1 (WNS +0.060): 16/16 boots detect the card, typed-burst 50/50. UART TX checked
  with fw/app/uart_burst.c + tools/uart_burst_check.py (fine); capture consoles with pyserial, not `cat` (cat garbles the log).
  iperf3 (2026-11-06): TX 70 Mb/s (CPU 94 % sys, 0 retx), RX 43.5 Mb/s (~3100 retx, softirq 67 %); bound by ~190 ns per 32-bit access in the Ethernet buffer
  window (memcpy_fromio), not DDR/cache. L2: no change; gzip baseline 13 s/3 MB recorded in l2-study.md; an L2 Linux image would be needed to measure it.
  RX loss = MAC drop counter (both 2 KiB slots full; CPU ~285 us/packet). Profile: ~30 % in the Ethernet IRQ handler (copy), ~55 % spread over the stack, no hotspot;
  more slots not worth it (pow2 limit: 4 max). DMA copy engine deferred to the PCIe/FMC work (needs the coherent hub; ceiling +15-25 Mb/s RX).
  Next: merge-ready bitstream is build/soc/vv_fan2 (vv_per1 plus the die-temperature register); SD data-in (sd_dat0) is an unsynchronized async input (report_cdc), harmless at present. Experiments irq_blank (SPI level
  with blanking) and uart_irq_hold were superseded and deleted.
- Status (2026-11-06, timing margin): vv_sync1 limit is the CPU's own logic at 333 MHz (WNS +0.060, WHS +0.010): 60 of the worst paths are Fetch L1 tag/way
  compare to the way RAMs (7-10 logic levels), GShare/BTB RAM addresses, and the DDR4 IP's internal paths; nothing in our RTL glue. More margin needs a CPU
  config change (fewer ways, drop gshare: costs IPC) or a lower ui_clk (DDR4-2400 = 300 MHz); not done. Run-to-run spread across builds is about +-0.07 ns.
- Status (2026-11-06, GMII IO): the RX input delays (+-0.5 ns "datasheet-memory") were wrong. Realtek RTL8211E(G) datasheet Rev 1.6 Table 64 (now in docs/external, confirmed): PHY RXD setup >= 2.5 ns, hold >= 0.5 ns to RXCLK; TXD needs setup 2.0 ns, hold 0 to GTX_CLK. With those, vv_sync1's RX_DV path fails by
  -1.313 ns (5 ns of route to the preamble checker) though the link works on hardware (real PHY output is better than the guarantee). Fix in feature/gmii-io-timing:
  input constraints 5.5/0.5, gmii_rx_reg stage on RXD/RX_DV/RX_ER. Results: with the datasheet constraints the RX domain meets setup +0.43..+0.76 ns, hold
  +0.03. Strategies: ExplorePostRoutePhysOpt -0.178, Explore -0.212, ExtraTimingOpt -0.015, then fpga/scripts/postroute_fix.tcl (phys_opt, Explore re-route, phys_opt)
  gave WNS +0.004 / WHS +0.011 (vv_io2q = the new reference bitstream, build/soc/vv_io2q/soc.bit). Board: 16/16 boots detect the SD card, link/DHCP/ping fine, CRC and
  preamble error counters 0, iperf3 RX 39 Mb/s / TX 69.5 Mb/s (unchanged). Open: trace skew between RXCLK and RXD not modelled; RXCLK period spec is 7.5-8.5 ns
  (constraint uses 8.0).
- Status (2026-11-06, vendor package): analysed docs/external/vendor_docs (not committed); notes in docs/hardware/vendor-reference.md. Its pins agree with our schematic
  extract (DDR4 67/67, SD, LED, HDMI, PCIe, QSFP refclk); no Ethernet/FMC/flash example. Open: its DDR4 IP uses part MT40A512M16LY-075 (2 GiB) vs our MT40A256M16GE-075E
  (1 GiB): test real DDR4 capacity/aliasing on the board; reuse its flash-boot bitstream properties (SPIx4, 51 MHz, compress) for the flash-boot task; sensor part MS5607 vs MS5611.
- Status (2026-11-06, DDR4 capacity): fw/app/ddr_full.c on vv_io2q: address lines + two full 992 MiB sweeps, 0 errors (before: 64 MiB). Window is 1 GiB so >1 GiB is
  untestable with this config; whether the parts are 4 Gb (ours) or 8 Gb (vendor IP) stays open: read the DRAM package marking, or build an 8 Gb config and test aliasing.
- Status (2026-11-08, DDR4 capacity): 8 Gb-controller build vv_d8g1 (-ddr8g, DDRHALF register 0xF8001024, fw/app/ddr_cap.c): the upper 1 GiB half aliases the lower one completely
  => parts are 4 Gb x16, 1 GiB total (closes the open item); SoC default config unchanged. docs/validation/ddr4-bringup.md.
- Status (2026-11-08, L2 with Linux): full-SoC images on the coherent hub: L2 128 KiB (WNS +0.020, WHS +0.010) and 256 KiB (WNS -0.154) vs no L2: gzip 13.5 -> 8.7 / 8.5 s, shell loop 2.8 -> 2.2 / 2.1 s,
  gunzip/md5sum/tar unchanged. Recommendation: coherent SoC + 128 KiB L2 as default (+2.2k LUT, 4 URAM); owner decision pending. docs/validation/l2-study.md.
- Status (2026-11-06, small peripherals): AXI GPIO + AXI Timer (PWM) + a second SPI master added; vv_per1 (WNS +0.003, WHS +0.010): DS18B20 via w1-gpio (30/30),
  MS5607 barometer via IIO (99.9 kPa; the part is an MS5607, not MS5611), fan via pwm-fan + tach (0..6000 rpm), buzzer works (owner heard it), 16/16 boots,
  Ethernet unchanged. See docs/validation/small-peripherals.md.
- Status (2026-11-06, fan governor): SYSMON die temperature in board register 0xF8001020 + userspace fan-governor (stop <40 C, start 45 C, 30 % to 100 % at 70 C, fail-safe full speed);
  vv_fan2 (WNS +0.012, WHS +0.010; vv_fan1 missed by 0.127), board-tested as above, 16/16 boots, Ethernet unchanged. Open: high-temperature behaviour untested, SYSMON constants from memory.
- Status (2026-11-07, flash boot): vv_fan2 written to the config flash (SPIx4, 51 MHz, compressed), verified; `-r` reconfigure from flash boots Linux (docs/validation/flash-boot.md).
  Finding: the flash probes as 128 Mb (JEDEC 0x20BB18), not the owner-stated 256 Mb MT25QU256: owner to confirm. Cold power-up from flash verified by the owner.
  Next: pause here (owner request); then PCIe/FMC. Simulation (tests/soc/run.sh) now defaults to the L2 netlist; both it and soc_base pass.
- Status (2026-11-12, Phase 0-7 review): checkboxes below updated against the repo and board. New: CI script/workflow (scripts/ci.sh), tests/dts, scripts/fetch_sources.sh, docs/versions.md pins, decisions/0002,
  docs/patches.md, docs/mvp-acceptance.md, tools/build_report.py, tools/smoke.py, scripts/release.sh. Board (vv_io2, WNS +0.008, WHS +0.010): LEDs/keys/switches in the AXI GPIO, two I2C buses (bus 1 finds both EEPROMs, bus 0 none),
  Ethernet on the L2 image TX 72 / RX 41 Mb/s (docs/validation/io-expansion.md). Found and fixed a UART RX interrupt loss (pulse interrupt vs PLIC gateway; irq_hold.v; console_stress 400/400 vs 0-51/400).
  Config flash now holds vv_io2 (2026-11-12, erase+write+verify, cold-reset boot, smoke 16/16). Not written: SD card (new image build/linux/sdcard.img) await the owner. Open: owner checks (keys/DIP/LEDs, PL_I2C U4, flash part), release/versioning.
- (older) Next: when build/soc/vv_333b.log shows EXIT=0, `openFPGALoader --cable ft232 build/soc/vv_333b/soc.bit`, then
  `tools/load.py fw/membench/build/membench_app.bin` to measure real L2-less latency vs the simulation model; then rerun L2 study on hardware;
  Linux-like workload; VexRiscv-SMP sim baseline.
- (superseded) close SoC timing at 333-350 MHz (sweep directives; consider CPU change on BTB/fetch path) and rerun on board; DDR4 speed decision
  (2667 supported by the part; CPU:DDR clock ratio cannot be 2:1 at 2667); update ddr4-bringup.md and decisions/0004; Linux-like workload; VexRiscv-SMP sim baseline (not done).
- Status: DDR4 bring-up design built (synth/impl/bitstream, timing met, tCK 1250) with RTL unit tests; NOT run on the board.
  See docs/validation/ddr4-bringup.md and decisions/0004. Open: PAR undriven (no CA parity), DCIRST-1 warning.
- Next (needs board on USB + JTAG path: FT232H, not Vivado-native -> openFPGALoader): program, read UART1 at 115200.
- Next: owner full pin list reconciles with schematic-pin-extract.csv; then Phase 1 DDR4/flash docs, CPU research
  (VexRiscv/VexiiRiscv/CVA6 Linux status); Vivado steps once installed.
- Open: first `release/` versioning scheme.

## Status legend

- `[ ]` Not started
- `[-]` In progress
- `[x]` Complete
- `[!]` Blocked / decision required

## Phase 0 — Repository and decision records

- [x] Create Git repository and initial commit containing `README.md`, `AGENTS.md`, and `TASKS.md`.
  - Acceptance: clean working tree after commit; README requirements and this plan are present.
- [x] Add license, `.gitignore`, contribution guidance, and a minimal directory layout.
  - Acceptance: no generated build output, licensed tools, credentials, or large artifacts are tracked.
- [x] Create `docs/versions.md` with pinned versions, upstream URLs, hashes where applicable, support end dates, and review dates. (2026-11-12: every build input pinned; scripts/fetch_sources.sh fetches at those commits; openFPGALoader version still unpinned)
  - Acceptance: each external dependency has an explicit version policy; no release build depends on a moving branch.
- [x] Create architecture and decision-record templates.
  - Acceptance: decisions record context, alternatives, decision, consequences, validation, and revisit triggers.

## Phase 1 — Hardware facts and risk retirement

- [-] Import/review the board schematic and identify exact board revision and component variants. (2026-11-12: inventory complete except the config-flash part number and the board revision, owner to confirm)
  - Acceptance: `docs/hardware/board-inventory.md` records pins, I/O standards, clocks, resets, buses, memory wiring, and evidence.
- [x] Map DDR4 devices, controller requirements, data/address width, capacity, byte lanes, reference clocks, calibration, and timing constraints. (2026-11-12: 2x x16 4 Gb parts, 1 GiB, verified on the board: calibration, 992 MiB sweeps, aliasing test; docs/validation/ddr4-bringup.md)
  - Acceptance: topology and capacity calculations independently reviewed; unknowns explicitly listed.
- [x] Map FPGA configuration flash, boot mode straps, SD wiring, serial bridge/JTAG path, and recovery procedure. (2026-11-12: SPIx4 flash boot from cold power-up, JTAG SRAM load, SD boot, tested factory restore: docs/validation/flash-boot.md, factory/; open: flash part 128 Mb vs the stated 256 Mb)
  - Acceptance: documented path to program a known-good bitstream and recover if the application image fails.
- [x] Inventory Ethernet PHY/MAC interface, clock/reset, MDIO, and connector mapping. (GMII 1000 Mb/s, RTL8211E, LiteEth; decisions/0003)
  - Acceptance: establish whether the first MVP network link is 1GbE and identify required IP/driver support.
- [x] Inventory I²C EEPROMs, pressure/temperature sensors, GPIO, LEDs, switches, keys, buzzer, HDMI, FMC, and optical transceivers. (board-inventory.md, confirmed vs unverified tagged per item)
  - Acceptance: interface matrix distinguishes confirmed wiring from unverified assumptions.
- [x] Find and evaluate board vendor reference designs, schematics, constraints, example projects, and licensing. (docs/hardware/vendor-reference.md; the vendor package is kept local, redistribution rights unknown)
  - Acceptance: each artifact has source URL/revision/license and a reuse decision; absence is documented.

## Phase 2 — CPU, SoC and build-system decisions

- [x] Evaluate VexRiscv/VexRiscv-SMP, VexiiRiscv, and CVA6 against a common rubric. (decisions/0001; CVA6 dropped by the owner, VexRiscv-SMP got synthesis numbers only, no board or simulated benchmark)
  - Acceptance: `docs/decisions/0001-cpu-selection.md` includes Linux port status, MMU, ISA width, toolchain, debug, licensing, integration complexity, estimated/actual area, Fmax, DDR performance, and remaining fabric.
- [x] Select at least two feasible finalists and establish a baseline synthesis/implementation flow. (VexiiRiscv and VexRiscv-SMP chosen 2026-10-18; out-of-context place-and-route Fmax for VexiiRiscv; VexiiRiscv selected as the CPU)
  - Acceptance: reports are generated for the actual XCKU5P part with board constraints; unknown/unsupported candidates are not scored as measured.
- [x] Compare Buildroot and Yocto against project needs and support horizon. (decisions/0002, written 2026-11-12 for the 2026-10-29 choice)
  - Acceptance: `docs/decisions/0002-linux-build-system.md` records the selected system, pinned release, rationale, upgrade policy, and revisit triggers.
- [-] Decide boot stages and development network boot method. (SD, flash and UART-loader boot decided and tested, decisions/0005; development network boot (TFTP/NFS) not done)
  - Acceptance: documented SD normal boot, TFTP/NFS or alternative dev boot if supported, and recovery flow.

## Phase 3 — Minimal hardware design

- [-] Establish Vivado project generation and reproducible command-line build. (build_soc.tcl, scripts/fetch_sources.sh; a build from a clean checkout has not been repeated)
  - Acceptance: clean checkout creates a project/build without GUI-only manual steps; Vivado version and license prerequisites are documented.
- [x] Implement clock/reset infrastructure and UART. (16/16 cold boots, resets recover)
  - Acceptance: timing constraints are explicit; serial console is reliable across reset and reboot.
- [x] Implement DDR4 controller and calibration path using supported IP or a validated reusable controller. (AMD DDR4 IP at DDR4-2667, calibrated on every boot, 992 MiB sweeps 0 errors)
  - Acceptance: calibration passes repeatedly; memory map and usable capacity are correct; memory stress test has no errors.
- [x] Add CPU, cache/MMU configuration, timer, interrupt controller, and interconnect. (VexiiRiscv RV64IMA, hub + 128 KiB L2, CLINT, PLIC, Sv39; Linux boots)
  - Acceptance: exact configuration is Linux-capable and boot firmware can enter the kernel with a valid memory map.
- [-] Add a deterministic address map and device-tree generation/check. (2026-11-12: tests/dts/run.sh checks the DTS against an independent map table; the DTS is still hand-written, not generated from RTL)
  - Acceptance: generated DTB matches the synthesized hardware; stale DTBs are rejected by build/release checks.
- [x] Add SD storage controller and minimum boot interface (2026-10-30: SPI-mode SD, spi_sifive.v + ROM driver; ROM boots OpenSBI+Linux from the card
  on the board; Linux mounts a read-only ext4 root and a persistent /data; decisions/0005, build `vv_sd2`). Not measured: ROM read speed, long-run reliability.
  - Acceptance: boot artifacts can be read reliably from the intended SD path.
- [x] Generate synthesis/implementation reports and initial resource/timing baselines. (2026-11-12: build_soc.tcl archives reports plus report.json via tools/build_report.py: tool version, commit, WNS/WHS, utilization, DRC)
  - Acceptance: utilization, Fmax/slack, DRCs, warnings, and report files are archived with tool version and source SHA.

## Phase 4 — First Linux boot and image build

- [x] Build the chosen boot firmware and document its relationship to FPGA configuration. (boot ROM -> OpenSBI -> kernel; decisions/0005, flash-boot.md)
  - Acceptance: boot stages, entry addresses, image formats, and failure recovery are documented.
- [x] Build a minimal Linux kernel with the required CPU architecture, console, timer, interrupt, memory, SD, and rootfs support. (linux/kernel/configure.sh, v6.18.59)
  - Acceptance: kernel config is versioned; kernel boots far enough to mount rootfs.
- [-] Create the device tree and validate it with kernel/device-tree tooling. (dtc builds warning-free and tests/dts checks the map; dtbs_check bindings validation not run)
  - Acceptance: CPU, memory, UART, interrupt controller, timer, SD, and Ethernet nodes match the hardware map.
- [-] Build the selected Buildroot/Yocto userspace. (reproducible config, 2 MB rootfs; the package list is packages-file-list.txt, no legal-info/source manifest yet)
  - Acceptance: reproducible image, package manifest, image size, and source/version manifest are generated.
- [x] Boot Linux from SD and establish serial-console recovery. (repeated cold and warm boots, 16/16; ROM falls back to the UART monitor)
  - Acceptance: repeated cold boot and warm reboot; expected RAM is visible; rootfs is writable only where intended.
- [ ] Add network-assisted development boot (TFTP/NFS or equivalent).
  - Acceptance: documented boot command and repeatable development cycle; SD remains the known-good fallback.

## Phase 5 — Minimum viable hardware validation

- [x] DDR functional and bandwidth tests. (ddr4-bringup.md: patterns, 992 MiB sweeps, bandwidth 8.6/4.6 GB/s AXI port, 350/516 MB/s CPU stream)
  - Acceptance: defined stress duration/patterns pass; bandwidth and clock configuration are recorded.
- [x] SD read/write and filesystem tests. (2026-11-12: tools/smoke.py --sd writes 16 MiB to /data, drops the page cache and reads it back identical, with no kernel I/O errors; no fio in the image, dd and md5sum used instead)
  - Acceptance: repeatable `fio` or equivalent tests pass without filesystem or I/O errors.
- [x] Ethernet link, DHCP/static configuration, ping, and throughput tests. (2026-11-06: link 1000 Mb/s, DHCP, ping, RX 3.05 MB/s over 3x40 MB wget with exact byte counts, vv_eth5; TX throughput, CPU load and error counters not yet measured - needs iperf3 in the rootfs) (2026-11-12: link 1000 Mb/s, DHCP, ping, iperf3 TX 70 / RX 39-43 Mb/s, CRC and preamble error counters 0; measured on the pre-L2 images, not repeated on the L2 image)
  - Acceptance: link negotiation is stable; throughput baseline, CPU load, and error counters are recorded.
- [-] GPIO, LEDs, switches, and keys. (2026-11-12: vv_io2 maps LED0-7, K1-K4, SW1-4 into the AXI GPIO with gpio-leds/gpio-keys-polled; LED loopback and idle key/switch state tested by tools/smoke.py; the owner still has to press the keys, flip the switches and see the LEDs: docs/validation/io-expansion.md)
  - Acceptance: all confirmed pins behave with documented polarity/debounce; automated smoke test returns pass/fail.
- [-] I²C bus discovery and safe device validation. (2026-11-12: two AXI IIC buses; bus 1 finds the two BL24C256 at 0x50/0x51 (blank) plus unidentified 0x58/0x59, bus 0 (PL_I2C, BL24C02) finds nothing: owner to check U4; no EEPROM written)
  - Acceptance: addresses are matched to schematic; EEPROM writes are avoided unless explicitly tested with backup/recovery.
- [x] Add pressure/temperature sensor drivers or verify upstream drivers for the exact components. (MS5607 via IIO, DS18B20 via w1; part is an MS5607, not an MS5611)
  - Acceptance: correct device identification, plausible readings, and documented units/error behavior.
- [x] Add buzzer and other low-risk peripherals where wiring allows. (gpio-beeper, pwm-fan with governor)
  - Acceptance: safe default state and simple test interface.
- [x] Create the userspace debug profile. (2026-11-12: busybox, iperf3, ethtool, i2c-tools, evtest, devmem, tools/smoke.py; rootfs cpio 3.4 MB, SD-config kernel 5.0 MB, 35 MB of 1 GiB used after boot)
  - Acceptance: package list includes selected networking, I²C/GPIO, storage, process/debug, and benchmark tools; image/RAM cost is measured.

## Phase 6 — CI and quality gates

- [x] Add GitHub Actions PR workflow for formatting, shell/Python tests, configuration checks, device-tree validation, and patch application. (2026-11-12: .github/workflows/pr.yml runs scripts/ci.sh; passes locally and on GitHub (run 43146540624 on develop, ubuntu-24.04, success))
  - Acceptance: workflow runs without Vivado or physical hardware for ordinary PRs.
- [x] Add a local scripted Vivado build with report extraction (no CI runner by project decision). (2026-11-12: build_soc.tcl archives report.json via tools/build_report.py; pass/fail gate by running the tool without --allow-negative-slack)
  - Acceptance: script archives utilization, timing, DRC, warnings, and build metadata; defined regressions fail the script.
- [x] Add RTL simulation/lint for custom logic. (2026-11-12: tests/rtl/run.sh Icarus + Verilator lint with committed mutants, tests/soc/run.sh Verilator system sim; no formal harness exists, the modules are small and are covered by exhaustive/model-based testbenches)
  - Acceptance: supported checks run automatically; unsupported constructs/tool limitations are documented.
- [x] Add a locally run hardware smoke test using serial capture and test scripts. (2026-11-12: tools/smoke.py, 18 checks, log archived per run; mutated copy fails as it should)
  - Acceptance: physical-board script verifies boot marker and available tests, archives logs, and identifies the board/bitstream/kernel revision.
- [-] Add release packaging with manifest and SHA-256 checksums. (2026-11-12: scripts/release.sh dry run packages 12 files with SHA256SUMS; reproducibility from a clean tagged commit untested, nothing tagged)
  - Acceptance: artifacts are reproducible from a clean tagged commit and include recovery instructions.

## Phase 7 — Upstreaming, optimization and MVP release

- [x] Review every local kernel/device-tree patch for upstreamability. (2026-11-12: docs/patches.md; no kernel patches, one VexiiRiscv patch)
  - Acceptance: each patch has purpose, base version, test evidence, and disposition.
- [-] Benchmark CPU candidates and optimization variants under comparable conditions. (VexiiRiscv variants measured in simulation and on the board; VexRiscv-SMP got synthesis numbers only)
  - Acceptance: CPU decision record contains measured resource/performance results and final approval.
- [-] Tune CPU clock, cache sizes, interconnect widths/arbitration, and DDR settings one variable at a time. (clock 333 MHz, L1/L2 sizes and DDR4 rate measured one at a time; interconnect width/arbitration not explored)
  - Acceptance: each accepted change meets the README resource/performance rule and passes timing closure plus functional regression.
- [-] Confirm final MVP acceptance criteria in README. (2026-11-12: docs/mvp-acceptance.md: 7 PASS, 4 PARTIAL, 0 open)
  - Acceptance: checklist is backed by logs/reports and physical-board evidence; unresolved items are clearly marked.
- [ ] Tag first MVP release and publish artifacts.
  - Acceptance: versioned bitstream, boot firmware, kernel, DTB, rootfs, manifest, checksums, build instructions, and recovery procedure are available.

## Deferred workstreams (not MVP blockers)

- [ ] HDMI input/output support after the board's actual signal path and PHY/IP requirements are confirmed.
- [ ] FMC HPC interface experiments and documented constraints.
- [ ] PCIe endpoint or host functionality, if the carrier wiring and use case justify it.
- [ ] 100G optical port: GTY transceiver bring-up, reference clocks, MAC/PCS/FEC, licensing, link partner, and performance validation. Keep isolated from MVP until explicitly reprioritized.
- [ ] Optional auxiliary microcontroller core for sensor/control functions if it demonstrably reduces CPU interrupts or simplifies architecture.
- [ ] Security hardening, signed boot/update, production image policy, and formal long-term maintenance plan if the platform moves beyond personal development use.

## Session handoff template

Append a short entry after each meaningful work session:

```text
### YYYY-MM-DD
- Completed:
- Evidence / commit:
- Tests run and results:
- Blockers / decisions needed:
- Next task:
```
