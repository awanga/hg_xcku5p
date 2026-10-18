# DDR4 bring-up design: evidence

Design: `fpga/rtl/ddr4_bringup_top.v` (ddr4_0 + `axi_memtest` + `status_uart`), constraints in `fpga/constraints/`, built by
`fpga/scripts/build_ddr4.tcl`. Evidence class for everything below: **simulation (unit) and Vivado implementation. No board test.**

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
- Bitstream not loaded: the board was not attached over USB when checked (no FT232H/CP2105 enumerated).
