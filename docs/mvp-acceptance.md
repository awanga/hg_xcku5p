# MVP acceptance status

Checked against the 11 criteria in README.md ("MVP acceptance criteria"). Status date 2026-11-12. Evidence is physical-board unless noted.
PASS = criterion met with recorded evidence; PARTIAL = part of it is missing (stated); OPEN = not started or blocked.

| # | Criterion | Status | Evidence / what is missing |
|---|---|---|---|
| 1 | Clean checkout reproduces bitstream and Linux artifacts | PARTIAL | `scripts/fetch_sources.sh` pins every source; `build_soc.tcl`, `gen_default_soc.sh`, `linux/build_sd.sh` build the artifacts. A build from a fresh clone has not been run end to end (the Buildroot rebuild, netlist generation and Vivado run were each done in the working tree). |
| 2 | FPGA configuration and recovery documented and tested | PASS | docs/validation/flash-boot.md (cold power-up from flash, JTAG load, `-r`), `factory/restore.sh` tested on the board, ROM falls back to the UART monitor when SD boot fails (decisions/0005). Open: the fitted flash part (128 Mb probed vs 256 Mb stated). |
| 3 | Linux boots from SD and exposes the DDR map | PASS | docs/validation/linux-bringup.md: Sv39, 1027268 kB of 1 GiB, 16/16 cold boots from SD. |
| 4 | UART, timer, interrupts, SD, Ethernet work reliably | PASS (bounded) | 16/16 boots detect the SD card, interrupts via `irq_sync` and `irq_hold` fixes (console stress 400/400), Ethernet 1000 Mb/s with DHCP, zero errors, TX 72 / RX 41 Mb/s on the L2 image. Not done: a multi-hour soak. |
| 5 | Rootfs has shell and debug tools, size and manifest recorded | PARTIAL | busybox, iperf3, ethtool, i2c-tools, evtest, devmem; cpio 3.4 MB, 35 MB RAM used after boot; file list from Buildroot (`packages-file-list.txt`, copied by `scripts/release.sh`). No package/license manifest (`make legal-info`) yet. |
| 6 | GPIO/LED/switch access; I2C discovery safe and validated | PARTIAL | vv_io2 (docs/validation/io-expansion.md): LED loopback and idle key/switch state tested, I2C bus 1 identified (both EEPROMs, read-only). Missing: owner presses keys, flips DIP switches, sees the LEDs; PL_I2C (BL24C02) does not answer; 0x58/0x59 unidentified. |
| 7 | DDR and SD tests clean; network and CPU/memory benchmarks recorded | PASS | DDR: docs/validation/ddr4-bringup.md. SD: `tools/smoke.py --sd` (16 MiB round trip, no I/O errors). Network: ethernet-bringup.md, io-expansion.md. CPU/memory: cpu-benchmarks.md, l2-study.md. |
| 8 | Resource and timing reports meet the baseline | PASS | `tools/build_report.py`: reference `vv_l2e128` WNS +0.020, WHS +0.010, 22678 LUT, 4 URAM, 44.5 BRAM, DRC warnings only (82 warnings, 2 advisories, no errors). No separate "agreed baseline" document existed; this build is the baseline. |
| 9 | Hosted CI passes; local Vivado build with archived reports; hardware smoke test | PASS | `scripts/ci.sh` + `.github/workflows/pr.yml` (GitHub run 43146540624 on develop: success), `build_soc.tcl` archives reports and `report.json`, `tools/smoke.py` 18/18 on vv_io2. |
| 10 | Every local patch has owner, rationale, test, disposition | PASS | docs/patches.md (no kernel patches; one VexiiRiscv patch). |
| 11 | Release artifacts with checksums, manifest, version, recovery | PARTIAL | `scripts/release.sh` (dry run packaged 12 files with verified SHA256SUMS). Nothing tagged or published; needs a versioning decision and the owner's approval to merge to `main`. |
