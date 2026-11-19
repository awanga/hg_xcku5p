# Flash boot and PCIe enumeration (CPU-less card, `-card`)

Question (owner, 2026-11-19): make sure a boot from the platform flash enumerates on a host root complex the way the firmware (bitstream) in the flash says.

## Facts
- The edge connector has **no EEPROM and no SMBus** (`docs/hardware/board-inventory.md`: PRSNT#1 tied to PRSNT#2 by 0R, SMBus/WAKE#/JTAG pins unconnected). The only EEPROMs (2 x BL24C256, BL24C02) sit on the FPGA's own I2C buses. A host reads vendor/device/subsystem IDs, class, revision and BAR sizes from the configuration space of the PCIe4 hard block, whose values are IP parameters (`PF0_*`) compiled into the bitstream. So the flash image **is** the identity; there is nothing else to update (the owner withdrew the EEPROM request after this was shown).
- Everything that decides what the host sees is therefore the build: it must come from one place and be checked, and the image must be configured in time.

## What the repository does now
| Item | Where |
|---|---|
| One identity manifest (vendor, device, subsystem vendor/ID, class, revision) | `fpga/pcie_identity.cfg` |
| IP settings applied from the manifest and read back; a rejected or rewritten property stops the build | `fpga/scripts/pcie/xdma_ip.tcl` (`read_identity`, `apply_identity`) |
| Gate on the generated hard-block parameters (`PF0_VENDOR_ID`, `PF0_DEVICE_ID`, `PF0_SUBSYSTEM_*`, `PF0_CLASS_CODE`, `PF0_REVISION_ID` in `*_pcie4_ip.v`) | `tools/pcie_identity.py check-ip`, called by `build_soc.tcl` after `generate_target` |
| The image carries its own record of the identity it was built with (`card_regs` PCI_ID/PCI_CLASS/PCI_SUBSYS at BAR0 + 0x1010/14/18, VERSION, BUILD commit id) | `fpga/rtl/card_regs.v`, generics from `pcie_identity.py generics` |
| Flash image that is never written by the script, with the programming command printed | `scripts/card_flash_image.sh`, `fpga/scripts/flash_bit.tcl` (optional CONFIGRATE argument, default 51 MHz) |
| Configuration time against the 100 ms PCIe budget | `tools/cfg_time.py` |
| On the bench (no host): identity words of the running image against the manifest, over the UART rig | `tools/card_smoke.py` (`identity`, `version`, `build_id`) |
| On the host, after enumeration: config-space IDs from sysfs and `lspci -nn -vv` against the manifest, and against the image's own record read through BAR0 | `tools/pcie_identity.py host-check <BDF>` (root) and `check-lspci [--text FILE]` |

Class code: the XDMA IP default is 07 00 01 (16450-compatible serial controller), which can make a host bind a serial driver; the manifest uses 05 80 00 (memory controller, other), as `vpcie` already did. **This changes the class of the endpoint builds** from the next build on (the v0.4.0 release builds and `vv_pcie4_flash.bit` still say 07 00 01 where they have the endpoint); no driver of this project depends on it.

## Result (2026-11-19, build `build/soc/card1`, commit 81df3ff plus the uncommitted work)
- `build_soc.tcl ... -card -strategy Performance_ExtraTimingOpt`: synthesis without critical warnings, `PCIE_IDENTITY identity OK`, WNS +0.185, WHS +0.010, 28.8k LUT, 38.5k FF, 63.5 BRAM, no URAM (the full CPU-less build with all peripherals, `ncp1`: WNS +0.354, WHS +0.003, 32.8k LUT, 43.0k FF, 71.5 BRAM). Stripping the peripherals saves about 4k LUT: the DDR4 controller, the XDMA core and the converters are most of the design.
- Board (JTAG load, flash untouched): `tools/card_smoke.py --reset build/soc/card1/soc.bit` passed 22 of 22 (identity words equal the manifest, VERSION 0.4.0, BUILD nonzero, DDR4, user window, `pcie_regs`, decode error, DDR words/burst/far). `pcie_regs` STATUS = 0x6 (core clock running, PERST# deasserted by the board pull-up, no link: no slot). Log `build/smoke/card-20261119-014320.log` (local).
- Unit tests: `tests/rtl/tb_card.v` (161 checks, Icarus and Verilator; 12 mutants, three survivors in the first run were fixed in the test: exact seconds period, writes at 0x40 reaching CTL[0], an equivalent kick mutant replaced); `tests/tools/test_pcie_identity.py` (24 tests, six tool mutants caught; one real tool bug found by it: a case-sensitive match on `Subsystem:`, and a wrong shift of the sysfs class value).

## The timing problem (not solved by this change)
`tools/cfg_time.py` on the flash images: 8.2 MB (`card1`, compressed, SPIx4) takes at least 322 ms at the verified 51 MHz; 9.9 MB (`vv_pcie4` endpoint image) 389 ms; the v0.4.0 release image (`vv_vpc3f`, 8.0 MB) is in the flash and boots Linux from it. Vivado's valid rates are 2.7 ... 85.0, 102.0, 127.5 MHz; even 127.5 MHz gives about 129 ms for the card image, and that rate **failed on this board** (2026-11-19: `card1_flash_r127.bit` written and verified, then `openFPGALoader -r`: STAT register 0x10800905, CRC error, DONE low, no rig reply; the flash was restored to the v0.4.0 image (`vv_vpc3f`, variant 2) afterwards). Rates between 51 and 127.5 MHz are untried, and none of them reaches 100 ms (164 MHz would be needed). So the image cannot meet the 100 ms from power-good that the PCI Express CEM specification allows before the card must answer. In practice:
- Cold boot of a PC: the firmware (BIOS) usually spends seconds before it scans the bus, so a card configured within about a second is normally found; a host that scans early, or a warm reset, can miss it.
- Recovery without a reboot: `echo 1 | sudo tee /sys/bus/pci/rescan` on the host once the card is configured (the DONE LED is lit).
- A guarantee needs Tandem configuration (stage 1 with the PCIe block and its clocks first, stage 2 afterwards). Owner approved pursuing it (2026-11-19). Finding, not a proof: the only Tandem property of the XDMA IP in Vivado 2026.1 is `CONFIG.enable_tandem_dfx`; with it true the generated IP is identical to false (compared file by file after renaming, only the module name differs) and no Tandem constraints appear, while this installation holds a Vivado **BASIC** licence (`INFO 17-3922`, expires 2027-10-18). AMD's PG213 lists Tandem PROM as a PCIe-block option, and a third-party summary says the Basic tier excludes Tandem and DFX; this was not confirmed from an AMD page (the page fetch returned HTTP 403). So the Tandem flow cannot be built here as is; it needs a licence that enables it (owner), and then a flow change (two-stage bitstream, flash layout) that could still not be verified without a host.

## Procedure (owner approval needed for the flash write)
1. `scripts/card_flash_image.sh build/soc/card1/soc.runs/impl_1/card_top_routed.dcp build/soc/card1_flash.bit [rate]` (writes only the image, prints the estimate and the command).
2. Owner: write the image with the printed `openFPGALoader` command; power-cycle.
3. On the host (a slot is needed; none on the bench): `sudo python3 tools/pcie_identity.py host-check 0000:01:00.0` and `python3 tools/pcie_identity.py check-lspci`. If the card is missing, rescan as above and, if it then appears, record the boot-order finding here.

## Not verified
- Any real enumeration: no host or slot on the bench. The check tools are tested on fixtures, not on a live lspci/sysfs.
- The class change 07 00 01 to 05 80 00 on a host.
- Configuration times are estimates from the file size and clock; neither the power-on delay nor a measured DONE time exists.
