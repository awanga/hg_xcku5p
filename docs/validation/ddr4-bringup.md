# DDR4 bring-up design: evidence

Design: `fpga/rtl/ddr4_bringup_top.v` (ddr4_0 + `axi_memtest` + `status_uart`), constraints in `fpga/constraints/`, built by
`fpga/scripts/build_ddr4.tcl`. Evidence classes are stated per section: simulation (unit), Vivado implementation, and board (2026-10-29).

## Simulation (`tests/rtl/run.sh`, 2026-10-18)
- axi_memtest: Icarus + Verilator, defect-free slave (with and without random stalls) plus 6 injected slave faults
  (bit flip, address alias, read hang, SLVERR write, early rlast, SLVERR read) each detected; 7 pattern vectors from the
  independent Python model (`tests/rtl/pattern_model.py`) match.
- Mutants caught: compare upper half dropped, rresp ignored, key not advanced, timeout disabled; status_uart letter, nibble order,
  uart stop bit.
- Not done: formal proof (AXI handshake property harness not written), simulation against the DDR4 IP/model, integration TB with ui_clk reset behaviour.

## Vivado 2026.1, xcku5p-ffvb676-2-i, tCK 1250 ps
- Synthesis, implementation (route) and bitstream complete. All user timing constraints met (WNS 1.259 ns).
- Utilization: 10374 CLB LUT (4.78 %), 13041 CLB registers (3.0 %), 25.5 BRAM tiles (5.3 %), 3 DSP, 83 bonded IOB.
  (Includes the controller's MicroBlaze MCS calibration, test engine, and UART.)
- DRC: 0 errors; warnings DCIRST-1 x26, PDCN-1569 x3, REQP-1877 x4, RTSTAT-10 x1 (see decision 0004). 0 critical warnings.

## Whole-window test on the Linux SoC (2026-11-06, vv_io2q, DDR4-2667, ui_clk 333.33 MHz)
`fw/app/ddr_full.c` (loaded with `tools/load.py`): address-line test (unique word at the base and at base + 2^k, k = 5..29) and two full sweeps
(hash of the address, then the inverted key; 992 MiB each, the first 32 MiB skipped for the program and stack). Result: 0 errors in all three steps, so every
address in the 1 GiB window is a distinct, working location; before this only 64 MiB had been swept.
Limits: the SoC window is 1 GiB (30-bit AXI address), so capacity above 1 GiB is not tested by this sweep (see the capacity section below for the 8 Gb-controller test). The controller is configured for MT40A256M16GE-075E (4 Gb x16,
15 row bits). If the parts were 8 Gb (the vendor's example IP says MT40A512M16LY-075), the extra row bit would simply be unused; the board's wiring cannot tell,
because A15/A16 share pins with CAS_n/RAS_n. Settling it needs the part marking on the DRAM packages (FBGA code) or an 8 Gb controller build that is tested for aliasing at
the top row bit; neither has been done.

## Capacity: 4 Gb parts, 1 GiB (2026-11-08)
Build `vv_d8g1` (`build_soc.tcl ... -ddr8g`, WNS +0.003 / WHS +0.013 after `postroute_fix.tcl`; strategy Performance_ExplorePostRoutePhysOpt missed by 0.003 first):
the controller is configured for MT40A512M16HA-075E (8 Gb x16, 16 row bits, 31-bit AXI address) and `ddr_halfmap.v` lets the CPU choose, through the DDRHALF register
(0xF8001024), whether the top 256 MiB of its window shows the lower or the upper 1 GiB of the controller's 2 GiB space. `fw/app/ddr_cap.c` fills each half with its own
hash (256 MiB per half), then reads both back, pushing dirty cache lines out before each switch.
Result: every word of the lower half read back as the upper half's hash (`other_half = 0x2000000` = all of half 0), the upper half read back correctly,
`bad = 0`. The top row bit (A15) is therefore ignored by the chips: **the parts are 4 Gb x16 per chip, 1 GiB in total**, as owner-stated and as in the schematic.
The vendor example's `MT40A512M16LY-075` setting over-declares the density. The 4 Gb configuration stays the SoC default; `-ddr8g` remains as the test build.
Limits: the test proves the upper half does not exist as separate storage with this controller mapping (ROW_COLUMN_BANK); it does not identify the chip markings.
Not part of this test: calibration at the 8 Gb setting was fine on the 4 Gb parts (the SoC booted Linux from SD on `vv_d8g1` afterwards).
