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
Limits: the SoC window is 1 GiB (30-bit AXI address), so capacity above 1 GiB is not tested. The controller is configured for MT40A256M16GE-075E (4 Gb x16,
15 row bits). If the parts were 8 Gb (the vendor's example IP says MT40A512M16LY-075), the extra row bit would simply be unused; the board's wiring cannot tell,
because A15/A16 share pins with CAS_n/RAS_n. Settling it needs the part marking on the DRAM packages (FBGA code) or an 8 Gb controller build that is tested for aliasing at
the top row bit; neither has been done.
