# HDMI output (1024x768@60, DVI-style TMDS, no input)

Bitstream `vv_hdmi2` (git 48ed73d, branch feature/hdmi-out): `soc_l2u_128k_w4`, Performance_ExtraTimingOpt, WNS +0.006 ns, WHS +0.012 ns, 25767 LUT, 45.5 BRAM, 4 URAM (`build/soc/vv_hdmi2/report.json`).
An earlier build (`vv_hdmi1`, default strategy plus post-route fix) missed timing by 0.066 ns on CPU fetch paths unrelated to HDMI; the HDMI clock domains and the irq synchronizer first stage are false-path/async-grouped in `soc_board.xdc`.

## Design
Mode 1024x768@60 (65 MHz pixel clock, 325 MHz 5x clock from a second MMCM), RGB565 frame buffer, 2048 bytes per line, line fetch through a read-only clock converter into the coherent DMA read port, ping-pong line buffer, own TMDS encoder and 10:1 ODDRE1 serializer. Registers at 0xF800F000 (see `fpga/rtl/hdmi_out.v`). Pins from the schematic extract; the TMDS pairs use DIFF_HSTL_I_12.

## Evidence
| Level | Result |
|---|---|
| Simulation | `tests/rtl/run.sh`: TMDS encoder vs 64 golden vectors from an independent Python encoder, full-path TB with a TMDS receiver model (Icarus and Verilator), 3 TMDS and 7 HDMI mutants all caught, lints clean. |
| Board, registers | MODE 0x04000300, FRAMES counts at about 60 per second, LINES counting, LATE 0, read-error bit clear, over minutes of scan-out. |
| Board, monitor | Owner-observed 2026-11-15: the monitor shows the Linux framebuffer console (kernel log) and text written to /dev/tty0. Linux registers `fb0` (simple-framebuffer, 1024x768 r5g6b5, 128x48 console). |

## Not verified / open
- HPD (STATUS bit0) reads 0 with a live monitor connected and the 5 V switch on. The picture does not depend on it. The schematic text extract does not show the HPD conditioning (R72 100K, "buffered" in the XDC comment is unconfirmed), so the pin level, polarity and the 5 V tolerance of the input are unresolved. Nothing uses HPD.
- No EDID (DDC not wired to the FPGA): the mode is fixed. Other monitors may reject 1024x768@60; one monitor was tested.
- Monitor +5 V backfeeds the board when the board is off and a live monitor is connected (owner observation: some LEDs light). The HDMI connector 5 V line comes from the TPS2051 switch, so this is a board-level behaviour; do not mistake it for the board being on (JTAG then reports "TDO is stuck at 0").
- Colour accuracy, tearing and long-run stability are not measured. Audio is not supported (DVI only).
