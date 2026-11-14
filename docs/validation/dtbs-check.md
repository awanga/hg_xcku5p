# Device-tree binding validation

Evidence: **host tool run** (2026-11-13), `tests/dts/dtbs_check.sh`: dt-validate (dtschema 2026.9) against the v6.18.59 binding schemas, on `hg-xcku5p-sdroot.dts`. The script fails on any finding not in
`tests/dts/dtbs_check_baseline.txt`; with an empty baseline it fails (checked). Fixed on the first run: gpio-keys child names (`switch-N`) and the SPI compatible (`sifive,fu540-c000-spi`, `sifive,spi0`).

Remaining 12 findings, all intentional or inherited:
- `hamgeek,hg-xcku5p` and `spinalhdl,vexiiriscv` compatibles have no binding (no upstream vendor binding is planned; personal platform).
- LiteEth: the local receive copy engine adds a fourth `reg` ("dma"), a second interrupt and `interrupt-names` (linux/patches/0001, docs/patches.md); the schema allows 3 regs and 1 interrupt.
- `xlnx,xps-gpio` wants `clocks`, `xlnx,xps-iic` rejects `clock-names`, `xlnx,xps-uartlite` rejects `clock-frequency`/`xlnx,baudrate`: properties the board's drivers or the earlier bring-up use; changing them needs a board test.
Not in hosted CI: the check needs the kernel sources and dtschema.
