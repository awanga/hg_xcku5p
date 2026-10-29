# Minimal SoC (VexiiRiscv RV64 + AMD DDR4 + boot ROM)

Status 2026-10-29. Evidence levels are stated per row: simulation, synthesis/implementation, board.

## Design
- `fpga/rtl/soc_top.v`: generated SoC netlist (`fpga/scripts/cpu/gen_soc.sh`, VexiiRiscv `SocGen`: CPU, TileLink fabric, AXI4 memory master 256-bit, AXI-Lite 32-bit peripheral master, CLINT/PLIC inside).
- CPU clock from CLK_50M via MMCM (1200 MHz VCO / `CPU_DIV`; 400 MHz at 3). Peripheral clock 100 MHz. DDR4 `ui_clk` from the AMD controller (200 MHz at tCK 1250 ps). All three are asynchronous; AMD `axi_clock_converter` on the memory (AXI4, 256-bit, 8-bit ID) and peripheral (AXI-Lite) paths.
- Peripherals behind `axi_crossbar`: UART lite 0xF8000000, board registers 0xF8001000 (`soc_regs.v`), boot ROM 0x10000000 (16 KiB). DDR4 at 0x40000000 (1 GiB). Reset vector 0x10000000.
- Firmware `fw/boot` (RV64IMA, runs from ROM, stack/bss in DDR4): banner, CPU kHz, DDR4 status, 16 MiB data pattern + address tests, throughput.
- `ui_clk`/CPU clock ratio: the CPU runs at twice the controller user clock at DDR4-1600.

## Results
| Item | Evidence | Result |
|---|---|---|
| `axil_simple`/`soc_regs`/`boot_rom` unit tests, 3 mutants | simulation (`tests/rtl/run.sh`) | pass; all mutants caught |
| Firmware on generated SoC netlist, DDR model, fault-injected read beat | simulation (`tests/soc/run.sh`, Verilator) | 2 clean passes; injected corruption reported |
| soc_base OOC place-and-route, 2.5 ns | implementation | WNS -0.433 ns (about 340 MHz); 8559 LUT, 9345 FF, 10 BRAM, 16 DSP |
| Full SoC, CPU 400 MHz, DDR4-1600, bitstream | implementation | WNS -0.546 ns (timing NOT met); 19128 LUT, 24399 FF, 39.5 BRAM, 0 URAM. Worst path: BTB BRAM -> fetch L1 BRAM address (core-internal) |
| DDR4 bring-up (axi_memtest) at tCK 1250 | board | calibrated, 214+ passes of 64 MiB, 0 errors; write ~5.0 GB/s, read ~2.9 GB/s at the AXI port |
| Full SoC bitstream above, boot ROM firmware | board | banner, `CPU clock: 400000 kHz`, `DDR4 calibrated: 1`, repeated 16 MiB pattern and address tests with 0 errors; CPU streaming write 230 MB/s, read 396 MB/s |

Caveat: the SoC image ran correctly at 400 MHz although static timing fails by 0.55 ns. That is a room-temperature run of a few minutes, not evidence of margin; do not rely on it.

## Board access
`openFPGALoader --cable ft232 <bit>`; console UART1 is `/dev/ttyUSB2`, 115200 8N1; VADJ jumper at 1.8 V.

## Open
- Close timing at the CPU clock (350 MHz or CPU change: BTB/fetch path); see TASKS.md.
- DDR4 speed sweep (tCK 1000, 750) on board: pending.
- L2/URAM study: see decisions/0001.
