# Development Plan and Progress

## Current status (<=100 lines; history in HISTORY.md)

- Decision: CPU study is VexRiscv/VexiiRiscv vs CVA6 (MicroBlaze V and Rocket Chip dropped, 2026-10-18).
  Reason: user direction. Status: README/AGENTS/TASKS updated; decision record 0001 started.
- Decision: no self-hosted CI runner; Vivado + hardware jobs run locally; hosted GitHub Actions only for non-licensed checks.
  Reason: user direction. Status: README/AGENTS/TASKS updated.
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
- [ ] Create `docs/versions.md` with pinned versions, upstream URLs, hashes where applicable, support end dates, and review dates.
  - Acceptance: each external dependency has an explicit version policy; no release build depends on a moving branch.
- [x] Create architecture and decision-record templates.
  - Acceptance: decisions record context, alternatives, decision, consequences, validation, and revisit triggers.

## Phase 1 — Hardware facts and risk retirement

- [-] Import/review the board schematic and identify exact board revision and component variants.
  - Acceptance: `docs/hardware/board-inventory.md` records pins, I/O standards, clocks, resets, buses, memory wiring, and evidence.
- [ ] Map DDR4 devices, controller requirements, data/address width, capacity, byte lanes, reference clocks, calibration, and timing constraints.
  - Acceptance: topology and capacity calculations independently reviewed; unknowns explicitly listed.
- [ ] Map FPGA configuration flash, boot mode straps, SD wiring, serial bridge/JTAG path, and recovery procedure.
  - Acceptance: documented path to program a known-good bitstream and recover if the application image fails.
- [ ] Inventory Ethernet PHY/MAC interface, clock/reset, MDIO, and connector mapping.
  - Acceptance: establish whether the first MVP network link is 1GbE and identify required IP/driver support.
- [ ] Inventory I²C EEPROMs, pressure/temperature sensors, GPIO, LEDs, switches, keys, buzzer, HDMI, FMC, and optical transceivers.
  - Acceptance: interface matrix distinguishes confirmed wiring from unverified assumptions.
- [ ] Find and evaluate board vendor reference designs, schematics, constraints, example projects, and licensing.
  - Acceptance: each artifact has source URL/revision/license and a reuse decision; absence is documented.

## Phase 2 — CPU, SoC and build-system decisions

- [ ] Evaluate VexRiscv/VexRiscv-SMP, VexiiRiscv, and CVA6 against a common rubric.
  - Acceptance: `docs/decisions/0001-cpu-selection.md` includes Linux port status, MMU, ISA width, toolchain, debug, licensing, integration complexity, estimated/actual area, Fmax, DDR performance, and remaining fabric.
- [ ] Select at least two feasible finalists and establish a baseline synthesis/implementation flow.
  - Acceptance: reports are generated for the actual XCKU5P part with board constraints; unknown/unsupported candidates are not scored as measured.
- [ ] Compare Buildroot and Yocto against project needs and support horizon.
  - Acceptance: `docs/decisions/0002-linux-build-system.md` records the selected system, pinned release, rationale, upgrade policy, and revisit triggers.
- [ ] Decide boot stages and development network boot method.
  - Acceptance: documented SD normal boot, TFTP/NFS or alternative dev boot if supported, and recovery flow.

## Phase 3 — Minimal hardware design

- [ ] Establish Vivado project generation and reproducible command-line build.
  - Acceptance: clean checkout creates a project/build without GUI-only manual steps; Vivado version and license prerequisites are documented.
- [ ] Implement clock/reset infrastructure and UART.
  - Acceptance: timing constraints are explicit; serial console is reliable across reset and reboot.
- [ ] Implement DDR4 controller and calibration path using supported IP or a validated reusable controller.
  - Acceptance: calibration passes repeatedly; memory map and usable capacity are correct; memory stress test has no errors.
- [ ] Add CPU, cache/MMU configuration, timer, interrupt controller, and interconnect.
  - Acceptance: exact configuration is Linux-capable and boot firmware can enter the kernel with a valid memory map.
- [ ] Add a deterministic address map and device-tree generation/check.
  - Acceptance: generated DTB matches the synthesized hardware; stale DTBs are rejected by build/release checks.
- [ ] Add SD storage controller and minimum boot interface.
  - Acceptance: boot artifacts can be read reliably from the intended SD path.
- [ ] Generate synthesis/implementation reports and initial resource/timing baselines.
  - Acceptance: utilization, Fmax/slack, DRCs, warnings, and report files are archived with tool version and source SHA.

## Phase 4 — First Linux boot and image build

- [ ] Build the chosen boot firmware and document its relationship to FPGA configuration.
  - Acceptance: boot stages, entry addresses, image formats, and failure recovery are documented.
- [ ] Build a minimal Linux kernel with the required CPU architecture, console, timer, interrupt, memory, SD, and rootfs support.
  - Acceptance: kernel config is versioned; kernel boots far enough to mount rootfs.
- [ ] Create the device tree and validate it with kernel/device-tree tooling.
  - Acceptance: CPU, memory, UART, interrupt controller, timer, SD, and Ethernet nodes match the hardware map.
- [ ] Build the selected Buildroot/Yocto userspace.
  - Acceptance: reproducible image, package manifest, image size, and source/version manifest are generated.
- [ ] Boot Linux from SD and establish serial-console recovery.
  - Acceptance: repeated cold boot and warm reboot; expected RAM is visible; rootfs is writable only where intended.
- [ ] Add network-assisted development boot (TFTP/NFS or equivalent).
  - Acceptance: documented boot command and repeatable development cycle; SD remains the known-good fallback.

## Phase 5 — Minimum viable hardware validation

- [ ] DDR functional and bandwidth tests.
  - Acceptance: defined stress duration/patterns pass; bandwidth and clock configuration are recorded.
- [ ] SD read/write and filesystem tests.
  - Acceptance: repeatable `fio` or equivalent tests pass without filesystem or I/O errors.
- [ ] Ethernet link, DHCP/static configuration, ping, and throughput tests.
  - Acceptance: link negotiation is stable; throughput baseline, CPU load, and error counters are recorded.
- [ ] GPIO, LEDs, switches, and keys.
  - Acceptance: all confirmed pins behave with documented polarity/debounce; automated smoke test returns pass/fail.
- [ ] I²C bus discovery and safe device validation.
  - Acceptance: addresses are matched to schematic; EEPROM writes are avoided unless explicitly tested with backup/recovery.
- [ ] Add pressure/temperature sensor drivers or verify upstream drivers for the exact components.
  - Acceptance: correct device identification, plausible readings, and documented units/error behavior.
- [ ] Add buzzer and other low-risk peripherals where wiring allows.
  - Acceptance: safe default state and simple test interface.
- [ ] Create the userspace debug profile.
  - Acceptance: package list includes selected networking, I²C/GPIO, storage, process/debug, and benchmark tools; image/RAM cost is measured.

## Phase 6 — CI and quality gates

- [ ] Add GitHub Actions PR workflow for formatting, shell/Python tests, configuration checks, device-tree validation, and patch application.
  - Acceptance: workflow runs without Vivado or physical hardware for ordinary PRs.
- [ ] Add a local scripted Vivado build with report extraction (no CI runner by project decision).
  - Acceptance: script archives utilization, timing, DRC, warnings, and build metadata; defined regressions fail the script.
- [ ] Add RTL simulation/lint for custom logic.
  - Acceptance: supported checks run automatically; unsupported constructs/tool limitations are documented.
- [ ] Add a locally run hardware smoke test using serial capture and test scripts.
  - Acceptance: physical-board script verifies boot marker and available tests, archives logs, and identifies the board/bitstream/kernel revision.
- [ ] Add release packaging with manifest and SHA-256 checksums.
  - Acceptance: artifacts are reproducible from a clean tagged commit and include recovery instructions.

## Phase 7 — Upstreaming, optimization and MVP release

- [ ] Review every local kernel/device-tree patch for upstreamability.
  - Acceptance: each patch has purpose, base version, test evidence, and disposition.
- [ ] Benchmark CPU candidates and optimization variants under comparable conditions.
  - Acceptance: CPU decision record contains measured resource/performance results and final approval.
- [ ] Tune CPU clock, cache sizes, interconnect widths/arbitration, and DDR settings one variable at a time.
  - Acceptance: each accepted change meets the README resource/performance rule and passes timing closure plus functional regression.
- [ ] Confirm final MVP acceptance criteria in README.
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
