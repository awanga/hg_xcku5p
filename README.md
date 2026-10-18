# HG-XCKU5P FPGA + Embedded Linux Platform

A reproducible FPGA firmware and embedded-Linux environment for the **HamGeek XCKU5P development board with FMCPCIE3.0 carrier**. The project aims to bring up a useful Linux-capable soft CPU, validate board peripherals, and leave as much FPGA fabric as practical for custom AXI peripherals and high-throughput datapaths.

> **Status:** Architecture and requirements planning. This repository plan is not evidence that the board already has a working reference design or that any listed peripheral is wired to a supported controller. Board-specific connectivity must be reconciled against the owner's schematics before implementation.

## Goals

- Boot a maintainable upstream-Linux-based system on the physical board.
- Use FPGA configuration flash for the bitstream and SD card for the normal Linux kernel/root filesystem.
- Support network-assisted development boot (TFTP/NFS or an equivalent workflow) when board Ethernet and boot firmware permit it.
- Keep local kernel/device-tree patches small, reviewable, and suitable for upstream submission.
- Provide practical shell, networking, storage, I²C, memory, and performance-debugging tools.
- Measure CPU performance, DDR throughput, timing closure, and FPGA resource use; avoid optimizations that fail the project's resource/performance acceptance rule.
- Maintain a versioned, reproducible relationship between RTL, constraints, device tree, kernel, rootfs, boot firmware, and release artifacts.

## Non-goals for the MVP

- 100G optical Ethernet support. The port is explicitly low priority and must not delay Linux bring-up.
- A general-purpose desktop distribution or graphical desktop.
- Supporting every peripheral before the first Linux boot.
- Assuming an external interface is usable merely because a connector or transceiver is present.
- Maintaining large private forks of Linux, Buildroot/Yocto, CPU cores, or vendor IP.
- Claiming safety, production, or security certification.

## Target hardware

The sales description lists the following. The authoritative source for pinout, polarity, bus connectivity, clocks, reset, voltage, memory topology, and transceiver routing is the owner's board schematic and the exact board revision.

| Listed component/interface | Initial software/firmware intent |
|---|---|
| AMD/Xilinx XCKU5P-FFVB676-2-i | Vivado device/part and timing target; confirm exact ordering-code interpretation in the project constraints |
| 2 × MT40A256M16GE-075E DDR4 (owner-stated; 32-bit total bus) | Two x16 4 Gb devices side by side give a 32-bit bus and 1 GiB. Confirm byte-lane/bank mapping, reference clock, calibration, and achievable data rate from schematic/controller validation |
| HDMI | Defer until Linux baseline; identify whether input, output, or both are actually routed and what PHY/bridge logic exists |
| Gigabit Ethernet | MVP networking if PHY/interface and clock/reset details are confirmed |
| FMC HPC | Document pin assignments and electrical constraints; future custom-I/O workstream |
| SD card | Normal kernel/rootfs storage, subject to controller and boot path |
| 2 × BL24C256 I²C EEPROM | Identify I²C bus/addressing; read-only identification first, avoid writes by default |
| MS5611 pressure module | Linux I²C/SPI bus and driver support to be confirmed from schematic |
| 8 LEDs, 4 toggle switches, 4 keys | GPIO/LED/input subsystem, with polarity/debounce documented |
| Serial/JTAG over USB-C | Console and FPGA programming/debug path; confirm which USB bridge and interfaces are present |
| Buzzer | GPIO/PWM or dedicated controller, based on schematic |
| 100G optical port | Out of MVP; document transceiver/GTY, reference-clock, MAC/PCS, licensing, and board routing requirements |
| MT25QU256ABA1EW9-0SIT QSPI flash (owner-stated) | FPGA configuration storage: 256 Mb, 1.8 V. Confirm config-bank voltage, boot-mode straps, and programming path from schematic |
| DS18820 temperature sensor (as listed) | Verify exact component identity and interface against schematic; do not assume spelling implies a specific supported driver |
| BL24C02 EEPROM | Confirm bus/address and use read-only access during discovery |
| Four-bit key input | GPIO/input with polarity and debounce defined |

### Board bring-up evidence

Before RTL integration, create `docs/hardware/board-inventory.md` from the schematic. For every interface, record:
- connector/component reference and exact part number;
- FPGA pins, I/O standards, bank voltage, polarity, pull-ups/downs;
- clock source, frequency, jitter/quality requirements, reset and sequencing;
- bus topology, address straps, interrupts, DMA paths, and transceiver lanes;
- existing reference RTL/IP, if any, and its license/version;
- verification method and confidence level.

Do not guess pin assignments or rely on the product page as a pin-level specification.

## Architecture

### Proposed direction

Use **AMD Vivado-centric integration**, with open-source CPU/firmware/software components wherever they reduce cost or improve maintainability. Vivado is responsible for supported UltraScale+ synthesis, implementation, timing analysis, bitstream generation, and hardware debug. Avoid a framework migration merely for ideological purity: reuse LiteX or other generators only where they interoperate cleanly with the board's actual memory, clocking, constraints, and peripheral design.

A generated SoC is acceptable if it can emit deterministic RTL/constraints and a device tree, and if generated files can be reproduced from versioned inputs. Keep board-specific glue and the address map explicit.

### Layering

1. **Board layer:** part, constraints, clocks, resets, pin assignments, memory and PHY wiring.
2. **SoC layer:** CPU, caches/MMU if available, interconnect, interrupt controller, timer, DDR4 controller, UART, SD, Ethernet, GPIO/I²C/SPI.
3. **Boot layer:** configuration flash loads the bitstream; a documented boot stage loads kernel, DTB, and optional initramfs from SD or network.
4. **Linux layer:** upstream LTS kernel, device tree, minimal local patch set, selected upstream drivers.
5. **Userspace:** Buildroot or Yocto image, init, BusyBox, debugging/network tools, test scripts.
6. **Validation layer:** simulation, lint/config checks, synthesis reports, timing reports, hardware smoke/performance tests.
7. **Release layer:** checksummed and versioned bitstream, boot firmware, kernel, DTB, rootfs, build metadata, and recovery instructions.

### Memory and boot strategy

Normal boot target:
- FPGA configuration flash: bitstream and, if needed, a minimal configuration/boot image.
- SD card: kernel, DTB, and persistent root filesystem.
- DDR4: kernel/userspace runtime memory, page cache, DMA buffers, and application workloads.
- Network-assisted development: TFTP for kernel/DTB and NFS root or an equivalent fast iteration mode, if Ethernet and boot firmware support it.
- Recovery: retain a known-good bitstream/boot path and provide a documented serial-console recovery procedure.

Do not reserve DDR4 for a full initramfs by default if the SD root filesystem is reliable. Keep a small initramfs as an optional recovery image. Report the memory map and all reserved regions (firmware, DMA, framebuffer, trace buffers, etc.) so RAM is not silently lost. Validate that the two DDR4 devices' wiring and controller configuration support the assumed capacity and width.

## CPU trade study

The CPU is a design gate. No candidate is approved until its **exact configuration** is demonstrated to support the intended Linux architecture and can be integrated with the board's memory and interrupt architecture.

### Candidates

| Candidate | Linux viability gate | Expected strengths | Risks/costs | Current position |
|---|---|---|---|---|
| **VexRiscv / VexRiscv-SMP** | Existing Linux-capable configurations and Linux-on-LiteX examples exist; verify current kernel port, SMP status, cache/MMU configuration, and generated SoC compatibility | Strong FPGA-oriented configurability, established open-source RISC-V ecosystem, good starting point for resource/performance exploration | Common Linux-capable configuration is RV32; generated RTL/tool dependencies and integration may be nontrivial; timing/area depend heavily on configuration | Strong resource-efficient baseline |
| **VexiiRiscv** | Verify current Linux-capable configuration, upstream kernel compatibility, toolchain, debug, and maintenance state at selection time | More ambitious RISC-V design with configurability and potential performance improvements over smaller configurations | Maturity and exact feature integration must be validated; potentially higher area and timing risk | Candidate where performance justifies extra area |
| **CVA6 (Ariane)** | Confirm current upstream Linux support, required privileged ISA/MMU/cache features, and exact integration path | 64-bit application-class RISC-V, standard software ecosystem, useful CPU-heavy workloads | Larger integration and fabric cost; timing closure at high frequency may be harder; board-specific SoC integration required | Strong 64-bit performance candidate |
| **MicroBlaze (classic)** | Check Linux support for exact configuration and current maintenance status; MicroBlaze V is out of scope | Deep Vivado integration and established bare-metal/RTOS use | Vendor-specific ISA/ecosystem and uncertain fit for current upstream-LTS Linux goal | Not preferred unless a proven Linux-capable reference design is found |
| **PicoRV32, Ibex, NEORV32** | Generally not a suitable default main CPU for full MMU-based Linux without a specific demonstrated configuration/port | Compact, understandable auxiliary controllers and peripheral CPUs | Usually unsuitable for the requested conventional Linux userspace | Exclude from main-CPU shortlist; consider for auxiliary control only |

### How to make the final decision

Run a controlled evaluation on the same board constraints and as comparable a memory/interconnect design as each core allows. Record:
- synthesis LUT/FF/BRAM/URAM/DSP use and incremental SoC overhead;
- post-implementation Fmax, slack, congestion, and whether timing closes at the target clock;
- cache sizes, MMU/TLB features, privilege architecture, interrupt/timer support, and Linux version/port status;
- DDR sustained bandwidth and latency, CPU benchmark results, context switching and interrupt latency;
- build complexity, upstream activity, licensing, toolchain maturity, debug support, and patch burden;
- remaining FPGA resources for custom AXI/datapath development.

Apply the project acceptance rule to each optimization: a 10% resource increase for a 100% performance increase is accepted; 10% resource for 10% performance requires a clear functional, simplicity, power, or workflow benefit; 10% resource for less than 10% performance is rejected. Define measurement noise and benchmark repeatability before applying this rule.

**Preliminary recommendation for final approval:** evaluate **CVA6** and **VexRiscv/VexiiRiscv** as the primary finalists. MicroBlaze V and Rocket Chip were dropped from the study by project decision (see `docs/decisions/0001-cpu-selection.md`). Favor the VexRiscv family if a Linux-capable configuration achieves the required workload with materially more fabric left over; favor CVA6 if 64-bit CPU performance and a conventional application-class environment provide a measured advantage that justifies the extra resources. Do not select a winner from nominal clock rate or core-only LUT counts.

## Linux build-system trade study

| Criterion | Buildroot | Yocto Project |
|---|---|---|
| Main strength | Straightforward generation of cross-toolchain, kernel, packages, and root filesystem | Layered metadata and highly configurable product/distribution builds |
| Learning/maintenance cost | Lower for a single board and compact image | Higher; more concepts, metadata, and build infrastructure |
| Reproducibility | Good with pinned releases, configs, source hashes, and controlled build inputs | Good with pinned layers, revisions, source mirrors, and controlled build inputs |
| Package/runtime model | Primarily builds an image; not a full package-feed workflow by default | Supports image generation and package feeds/package management workflows |
| Product variants and BSP layers | Works, but complex multi-product customization can become awkward | Strong for multiple products, machine layers, distro policies, and vendor BSPs |
| LTS model | 2025.02 LTS series is supported through March 2028 according to the current release page; re-check at project kickoff | Yocto 6.0 LTS (“Wrynose”) is listed as supported through April 2030; verify exact support terms and vendor policy |
| Fit here | **Recommended for MVP**: one board, compact rootfs, small local patch set | Prefer if the project grows into multiple maintained products, formal BSP layers, or package-feed requirements |

Recommendation: **Buildroot for the initial platform**. Keep kernel and bootloader integration cleanly separated so moving to Yocto later does not require redesigning the hardware layer. Revisit this choice if a package-managed runtime, multiple product variants, or longer formal product-support process becomes a concrete requirement.

## Kernel and upstream policy

- At project kickoff, select the newest upstream Linux LTS that is compatible with the chosen CPU and required drivers. Record kernel version, upstream release URL, support end date, and review date in `docs/versions.md`.
- Do not hard-code a kernel version solely because it was current during planning. Verify upstream LTS status and architecture support before pinning it.
- Prefer upstream drivers and device-tree bindings. Avoid out-of-tree drivers where an upstream driver can be extended.
- Keep patches in a quilt-style or clearly ordered patch directory, each with an explanatory commit message and upstream status (`local`, `submitted`, `accepted`, `not upstreamable`).
- Do not carry unrelated cleanup or generated-file diffs in kernel patches.
- Rebase patches regularly enough to detect drift; document a review cadence and security-fix process.

## Userspace requirements

MVP image should include:
- BusyBox with a usable shell, init, coreutils, mount, process and log utilities;
- `iproute2`, `ethtool`, `ping`/`iperf3` or equivalents for network diagnostics;
- `i2c-tools`, SPI/GPIO utilities appropriate to the selected kernel interfaces, and `usbutils` if USB host support exists;
- `fio`, a RAM test, storage checks, and benchmark scripts where architecture/resources permit;
- `strace`, `gdb`/`gdbserver`, `perf` where supported, and kernel tracing tools only when justified by image size;
- device-tree inspection, kernel logs, temperature/pressure readout, GPIO/LED/switch smoke tests, and a self-test summary;
- SSH only if useful and configured securely; serial console remains the mandatory recovery/debug path.

Record the installed package list and image size. Optional debug packages should be selectable so production-like images can be smaller.

## CI/CD proposal

Use **GitHub Actions hosted runners** for repository checks only. **No self-hosted runner is established** (project decision): Vivado builds and hardware smoke tests are run locally by the maintainer using the same scripts the CI would call, and their reports/logs are recorded in the repository or release notes. Keep scripts portable so a runner can be added later if the decision changes.

### Pull-request checks (fast)

- Markdown lint and link checks where practical.
- Python/shell lint and unit tests for scripts.
- Validate Kconfig fragments, Buildroot external tree/configuration, device-tree syntax, and patch application.
- RTL lint/simulation using open tools where compatible; unit tests for custom RTL.
- Ensure all source dependencies are pinned to tags/commits and all local patches apply cleanly.
- Do not require physical board access for ordinary pull requests.

### Local Vivado build (no CI runner)

- Run locally with an explicit Vivado version (see `docs/versions.md`) via a single scripted entry point.
- Synthesize and implement the baseline design; capture utilization, timing, clock interaction, and DRC reports.
- Fail on errors, unexpected critical warnings, missing constraints, or timing violations for required clocks.
- Compare resource and timing reports against checked-in baselines with reviewed tolerances; never silently overwrite baselines.
- Cache downloaded source archives/toolchain outputs only when cache keys include versions and hashes. Do not cache opaque Vivado state as a substitute for reproducible builds.
- Avoid exposing secrets/license details in logs or committed reports.

### Local hardware smoke tests

- Flash/load a known bitstream and boot image on the board.
- Capture UART output and require a boot marker plus self-test pass.
- Run DDR, SD, Ethernet, I²C, GPIO and sensor smoke tests as each becomes available.
- Archive logs, build manifests, checksums, bitstream, DTB, kernel and rootfs artifacts.
- Label tests as `simulated`, `synthesized`, `board-tested`, or `not tested`; never treat simulation as proof of board operation.

### Release workflow

- Build from a clean, tagged commit with pinned inputs.
- Produce a manifest with Git SHA, dirty-tree state, tool versions, source revisions, configuration hashes, build date, and artifact SHA-256 sums.
- Publish versioned artifacts and recovery instructions only after hardware smoke tests pass.
- Require a human approval step for release tags and any change that modifies boot flash programming or the known-good recovery path.

## Proposed repository layout

```text
.
├── README.md
├── AGENTS.md
├── TASKS.md
├── LICENSE
├── .gitignore
├── .github/
│   └── workflows/
│       └── pr-checks.yml
├── docs/
│   ├── architecture.md
│   ├── versions.md
│   ├── hardware/
│   │   ├── board-inventory.md
│   │   ├── boot-and-recovery.md
│   │   └── interface-matrix.md
│   ├── decisions/
│   │   ├── 0001-cpu-selection.md
│   │   └── 0002-linux-build-system.md
│   ├── validation/
│   │   └── benchmark-methodology.md
│   └── bringup/
├── fpga/
│   ├── constraints/
│   ├── rtl/
│   ├── ip/
│   ├── scripts/
│   └── reports/.gitkeep
├── boot/
│   ├── config/
│   └── scripts/
├── linux/
│   ├── kernel.config
│   ├── device-tree/
│   └── patches/
├── buildroot/
│   ├── external.desc
│   ├── Config.in
│   ├── external.mk
│   ├── configs/
│   ├── board/hg_xcku5p/
│   └── package/
├── tests/
│   ├── unit/
│   ├── rtl/
│   ├── host/
│   └── hardware/
├── scripts/
│   ├── check-env.sh
│   ├── build.sh
│   ├── package-release.sh
│   └── capture-uart.sh
└── artifacts/                 # generated; normally not committed
```

Do not create empty scaffolding for every directory on day one. Add directories when the corresponding task begins. Never commit licensed Vivado binaries, credentials, private keys, or large generated build trees.

## Git and contribution workflow

- Use Git from the first commit. Keep `main` buildable; use short-lived feature branches and pull requests.
- Prefer descriptive commit subjects; do not use numbered commit messages.
- Make one logical change per commit. Include rationale and validation evidence for hardware-affecting changes.
- Track external source revisions explicitly; use submodules or scripted pinned checkouts only when their maintenance cost is understood.
- Commit human-authored configs, scripts, constraints, device trees, patch files, and benchmark baselines. Ignore reproducible generated output unless a specific release or review need justifies retaining it.
- Every change to clocks, DDR, address maps, CPU configuration, or boot flow must update the architecture/decision documentation and relevant acceptance tests.
- Never report hardware tests as passed unless the test ran on the physical board.

## MVP acceptance criteria

The MVP is complete when all applicable criteria below pass on the physical board and evidence is recorded:

1. A clean checkout and documented toolchain can reproduce the bitstream and Linux artifacts.
2. FPGA configuration and recovery procedure are documented and tested.
3. Linux boots from the intended SD-card path and exposes the expected DDR memory map.
4. UART console, timer, interrupts, SD storage, and at least one Ethernet interface work reliably.
5. Rootfs has a useful shell and selected hardware-debug tools, with image size and package manifest recorded.
6. Board GPIO/LED/switch access works; I²C discovery is safe and identified EEPROM/sensor devices are validated against the schematic.
7. DDR and SD tests complete without errors; network throughput and CPU/memory benchmarks are recorded.
8. FPGA resource and timing reports meet the agreed baseline; no required clock has an unexplained timing failure.
9. Hosted CI checks pass; the local Vivado build passes with archived reports; hardware smoke test is scripted or its manual procedure and evidence are documented.
10. Every local kernel patch has an owner, rationale, test, and upstream disposition.
11. Release artifacts include checksums, build manifest, version information, and recovery instructions.

## Key risks

- No known-good board-specific reference design may exist.
- DDR4 controller and PHY integration/calibration may dominate bring-up time.
- A selected CPU may lack the exact MMU/Linux configuration expected, or its integration may be too costly.
- Vivado licensing and version pinning constrain reproducibility; Vivado builds are local-only (no CI runner).
- Sensor/component names in marketing material may be inaccurate; confirm exact part numbers from schematics.
- Some interfaces may need licensed AMD IP or substantial custom logic.
- Linux driver availability depends on the actual bus wiring and controller implementation, not the component name alone.
- High CPU frequency is limited by the implemented critical path, memory latency, and timing closure—not just the CPU's nominal target clock.

## References

- Board sales page: <https://www.hgeek.com/products/hamgeek-xcku5p-development-board-fmcpcie3-0-hdmi-compatible-100g-gigabit-ethernet-for-fpga-development>
- AMD Vivado Design Suite: <https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vivado.html>
- Linux kernel releases: <https://www.kernel.org/>
- Buildroot release and LTS information: <https://buildroot.org/download.html> and <https://buildroot.buildroot.org/lts.html>
- Yocto Project release policy: <https://docs.yoctoproject.org/dev/ref-manual/release-process.html>
- Linux on LiteX/VexRiscv reference implementation: <https://github.com/litex-hub/linux-on-litex-vexriscv>
- LiteX board definitions: <https://github.com/litex-hub/litex-boards>
- LiteX supported CPUs: <https://github.com/enjoy-digital/litex/wiki/CPUs>

## Document maintenance

This README is the human-oriented introduction and primary requirements reference. Keep detailed design decisions in `docs/decisions/`, tool versions in `docs/versions.md`, and actionable progress in `TASKS.md`. `AGENTS.md` provides concise execution rules and points agents back here for requirements.
