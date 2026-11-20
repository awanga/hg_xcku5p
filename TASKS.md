# Development Plan and Progress

## Current status (<=100 lines; history in HISTORY.md)

- Decision: CPU study is VexRiscv/VexiiRiscv vs CVA6 (MicroBlaze V and Rocket Chip dropped, 2026-10-18).
  Reason: user direction. Status: README/AGENTS/TASKS updated; decision record 0001 started.
- Decision: no self-hosted CI runner; Vivado + hardware jobs run locally; hosted GitHub Actions only for non-licensed checks.
  Reason: user direction. Status: README/AGENTS/TASKS updated.
- Decision: default SoC = coherency hub + 128 KiB 4-way L2 in UltraRAM (soc_l2u_128k_w4, fpga/scripts/cpu/gen_default_soc.sh), owner-approved 2026-11-08.
  Reason: gzip 1.55x, shell 1.28x under Linux, timing met. Status: docs/decisions/0006-l2-cache.md; vv_l2e128 (WNS +0.020, WHS +0.010) is the L2 reference; the config flash now holds vv_dma3 (L2 + LED/key/I2C + Ethernet DMA, WNS +0.001).
- Decision: board memory/flash (owner-stated, NOT yet schematic-verified): config flash MT25QU256ABA1EW9-0SIT;
  DDR4 2 x MT40A256M16GE-075E, 32-bit bus (1 GiB). Status: recorded in docs/hardware/board-inventory.md.
- Decision: MIT license (docs/licensing.md); deps checked, no conflict. Schematic PDF kept local (gitignored).
- Decision: Ethernet runs GMII (board default); RGMII optional via R158 rework (0003-ethernet-gmii.md).
- Decision (2026-10-18): finalists VexiiRiscv + VexRiscv-SMP; prefer 64-bit but minimise BRAM; LiteEth accepted; AMD DDR4 IP
  preferred with LiteDRAM USPDDRPHY kept as alternative pending hardware speed. README updated (needs approval before commit).
- Decision (user, 2026-10-29): CPU and DDR4 share one clock (ui_clk, 333.33 MHz at DDR4-2667). Status: SoC bitstream (build/soc/vv_333)
  met timing (WNS +0.006, ExplorePostRoutePhysOpt) and ran on the board: 0 errors, CPU stream write/read 350/516 MB/s. UART loader
  (fw/boot, tools/load.py, 921600 baud) passes simulation; bitstream build/soc/vv_333b with the loader was started and NOT yet loaded on the board.
- Status (2026-11-12, Phase 0-7 review): checkboxes below updated against the repo and board. New: CI script/workflow (scripts/ci.sh), tests/dts, scripts/fetch_sources.sh, docs/versions.md pins, decisions/0002,
  docs/patches.md, docs/mvp-acceptance.md, tools/build_report.py, tools/smoke.py, scripts/release.sh. Board (vv_io2, WNS +0.008, WHS +0.010): LEDs/keys/switches in the AXI GPIO, two I2C buses (bus 1 finds both EEPROMs, bus 0 none),
  Ethernet on the L2 image TX 72 / RX 41 Mb/s (docs/validation/io-expansion.md). Found and fixed a UART RX interrupt loss (pulse interrupt vs PLIC gateway; irq_hold.v; console_stress 400/400 vs 0-51/400).
  Config flash now holds vv_io2 (2026-11-12, erase+write+verify, cold-reset boot, smoke 16/16). Eth DMA (merged): vv_dma3 (WNS +0.001) is in the config flash; RX 46.2 Mb/s vs 41.3, 0 errors, smoke 19/19 (docs/validation/eth-dma.md). Fan curve reworked. Full SD image written 2026-11-13: new fan curve verified on the board (34.4 C -> duty 44, smoke 19/19). Open: owner checks (keys/DIP/LEDs, PL_I2C U4, flash part), release/versioning.

- Status (2026-11-20): v0.4.1 released (tag on main; CPU-less card build `-card` with reference function block, user interrupts, `-umem N` DDR4 ports; PCIe identity from `fpga/pcie_identity.cfg`).
  Config flash holds a `-vpcie` build from develop (vv_vpc4f, flash-boot smoke PASS). Package build/release/0.4.1 (32 files, includes the card images). Older status entries moved to HISTORY.md.
  Next: docs/v1.0-plan.md (proposed v1.0 scope, open items sorted into agent / owner / decisions; owner decisions D1-D5 pending). Flash-boot soak: 40/40 passed (owner skipped the longer run).

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

- [-] Establish Vivado project generation and reproducible command-line build. (build_soc.tcl, scripts/fetch_sources.sh; clean-clone chain (fetch, ROM, netlist, Vivado) reproduced identical netlist, WNS +0.001/WHS +0.011; submodule fetch fixed; Linux image not rebuilt from the clone)
  - Acceptance: clean checkout creates a project/build without GUI-only manual steps; Vivado version and license prerequisites are documented.
- [x] Implement clock/reset infrastructure and UART. (16/16 cold boots, resets recover)
  - Acceptance: timing constraints are explicit; serial console is reliable across reset and reboot.
- [x] Implement DDR4 controller and calibration path using supported IP or a validated reusable controller. (AMD DDR4 IP at DDR4-2667, calibrated on every boot, 992 MiB sweeps 0 errors)
  - Acceptance: calibration passes repeatedly; memory map and usable capacity are correct; memory stress test has no errors.
- [x] Add CPU, cache/MMU configuration, timer, interrupt controller, and interconnect. (VexiiRiscv RV64IMA, hub + 128 KiB L2, CLINT, PLIC, Sv39; Linux boots)
  - Acceptance: exact configuration is Linux-capable and boot firmware can enter the kernel with a valid memory map.
- [x] Add a deterministic address map and device-tree generation/check. (2026-11-13: tests/dts/run.sh checks the DTS against an independent map table and tests/dts/xbar_map.py checks the crossbar ranges in build_soc.tcl against tests/dts/xbar_map.csv, both in scripts/ci.sh; the DTS stays hand-written by decision, the check is the guard)
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
- [x] Create the device tree and validate it with kernel/device-tree tooling. (2026-11-13: dtc warning-free, address/IRQ map test, tests/dts/dtbs_check.sh against the v6.18.59 binding schemas: 12 documented known findings, docs/validation/dtbs-check.md)
  - Acceptance: CPU, memory, UART, interrupt controller, timer, SD, and Ethernet nodes match the hardware map.
- [x] Build the selected Buildroot/Yocto userspace. (2026-11-13: reproducible config, 3.4 MB rootfs, scripts/legal_info.sh produced the licence and source manifest: docs/legal/)
  - Acceptance: reproducible image, package manifest, image size, and source/version manifest are generated.
- [x] Boot Linux from SD and establish serial-console recovery. (repeated cold and warm boots, 16/16; ROM falls back to the UART monitor)
  - Acceptance: repeated cold boot and warm reboot; expected RAM is visible; rootfs is writable only where intended.
- [-] Add network-assisted development boot (TFTP/NFS or equivalent). (2026-11-13: NFS-root variant built: linux/dts/hg-xcku5p-sdnfs.dts, KNFS=1 kernel option, scripts/nfs_dev_setup.sh; the host export needs root, so the boot is not yet tested: owner runs `sudo scripts/nfs_dev_setup.sh`)
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
- [x] Benchmark CPU candidates and optimization variants under comparable conditions. (2026-11-13: VexiiRiscv variants measured in simulation and on the board; VexRiscv-SMP synthesis-only by decision, RV32 cannot run the RV64 stack: docs/decisions/0007; owner confirmed 2026-11-14)
  - Acceptance: CPU decision record contains measured resource/performance results and final approval.
- [x] Tune CPU clock, cache sizes, interconnect widths/arbitration, and DDR settings one variable at a time. (2026-11-13: clock, L1/L2 and DDR4 rate measured one at a time; width and arbitration have no alternative to compare: docs/decisions/0007; owner confirmed 2026-11-14)
  - Acceptance: each accepted change meets the README resource/performance rule and passes timing closure plus functional regression.
- [-] Confirm final MVP acceptance criteria in README. (2026-11-12: docs/mvp-acceptance.md: 7 PASS, 4 PARTIAL, 0 open)
  - Acceptance: checklist is backed by logs/reports and physical-board evidence; unresolved items are clearly marked.
- [ ] Tag first MVP release and publish artifacts.
  - Acceptance: versioned bitstream, boot firmware, kernel, DTB, rootfs, manifest, checksums, build instructions, and recovery procedure are available.

## Deferred workstreams (not MVP blockers)

- [x] HDMI output (input excluded by owner): 1024x768@60 DVI-style TMDS, fb console on a monitor. (2026-11-15: docs/validation/hdmi-output.md; HPD unresolved, one monitor tested, no EDID. HDMI input not built: owner decision)
- [ ] FMC HPC interface experiments and documented constraints.
- [-] PCIe endpoint or host functionality, if the carrier wiring and use case justify it. (2026-11-15: endpoint built (`build_soc.tcl -pcie`, WNS +0.000), verified in xsim with the vendor root-port bench and on the board at register level; link/DMA on silicon untested (no slot): docs/validation/pcie-endpoint.md. Variants without the hard IP: docs/decisions/0008, proposal. Refclk: edge connector = bank 224 REFCLK0 (used by the endpoint build), X2 = bank 225 REFCLK1 (reserved for a host build), owner-stated 2026-11-15)
  Variant 2 stage 1 (logical root complex, decision 0008): done and board-tested 2026-11-15 (docs/validation/vpcie-root-complex.md); stage 2 (XDMA-compatible DMA subset, vdma.v) done and board-tested 2026-11-16 (all smoke --vpcie checks pass); stage 3 (MSI) optional. Variant 3 (CPU-less, docs/validation/pcie-only.md): stage A (nocpu_core + UART2 rig) board-tested 2026-11-17, 13/13 rig_smoke checks; stage B (-nocpu -pcie, host BAR0 on the peripheral crossbar): pcie_ep_nocpu xsim test passes, build WNS +0.354 (not loaded on the board). Lean card (-card, 2026-11-19, docs/validation/pcie-flash-enumeration.md): DDR4 + PCIe + UART2 rig + card_regs/user_regs hook window, WNS +0.185, card_smoke 22/22 on the board; PCIe identity from one manifest (fpga/pcie_identity.cfg) checked at build; the edge connector has no EEPROM, so the flash image is the identity. Release 0.4.1 (2026-11-20): default `-card` build (VERSION 0.4.1, 2 user ports, WNS +0.166, WHS +0.010, 31.3k LUT) board-tested 27/27; develop RTL suite, xsim and CI pass. Flash holds a CPU+peripheral `-vpcie` build from develop (`vv_vpc4f`, 51 MHz, WNS +0.002 after postroute_fix, written and verified 2026-11-20 with owner approval; `smoke.py --reset flash --vpcie` PASS 0 failed, log build/smoke/20261120-141356.log; the v0.4.0 image vv_vpc3f held it before;  `smoke.py --reset flash --vpcie` PASS, 0 failed, log build/smoke/20261119-110438.log; first I wrote the endpoint image vv_pcie4_flash by mistake, it panicked against the vpcie SD kernel, replaced). 127.5 MHz CONFIGRATE test failed on the board (CRC error); flash restored. OPEN: the 8.2 MB image configures in >= 322 ms (budget 100 ms); Tandem looks blocked by the Basic licence (IP option has no effect; owner: licence or accept rescan), owner accepted the rescan fallback (2026-11-19); `-card` gained the 16 KiB `user_ip` window at BAR0 + 0x4000 (build card2 WNS +0.284, card_smoke 23/23), then user interrupts (8 XDMA vectors, irq_req.v) and `-umem N` user DDR4 ports with a self-test per port (mem_probe.v): 14 ports close timing (WNS +0.107, 42.4k LUT), 4 ports were board-tested with the first probe; final RTL (card_u14) board-tested 2026-11-20 after the owner restored board power: card_smoke 39/39 with 14 ports (default stays -umem 2, owner decision); no link, so MSI delivery is unverified; the card image is not in the flash, class code changes 07 00 01 to 05 80 00 in the next endpoint build.
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
