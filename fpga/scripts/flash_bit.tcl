# Write a flash-bootable bitstream from a routed checkpoint (timing is unchanged; only config options differ).
# Usage: vivado -mode batch -source fpga/scripts/flash_bit.tcl -tclargs <routed.dcp> <out.bit> [configrate_mhz]
# configrate_mhz defaults to 51 (the verified rate). A higher rate shortens the configuration, which matters for a PCIe card (tools/cfg_time.py), but has not been
# tried on this board's flash: flash it only with owner approval and check the boot afterwards.
# Programming: openFPGALoader --cable ft232 --freq 3000000 --fpga-part xcku5p-ffvb676 -f --verify --unprotect-flash <out.bit>
# 3-byte addressing: the probed flash is 128 Mb (docs/validation/flash-boot.md) and the image is under 16 MiB.
if {$argc < 2 || $argc > 3} { error "usage: -tclargs <routed.dcp> <out.bit> [configrate_mhz]" }
lassign $argv dcp out rate
if {$rate eq ""} { set rate 51.0 }
set rate [format %.1f $rate]   ;# Vivado accepts 2.7 5.3 8.0 10.6 21.3 31.9 36.4 51.0 56.7 63.8 72.9 85.0 102.0 127.5
open_checkpoint $dcp
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE $rate [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
write_bitstream -force $out
