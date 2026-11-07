# Write a flash-bootable bitstream from a routed checkpoint (timing is unchanged; only config options differ).
# Usage: vivado -mode batch -source fpga/scripts/flash_bit.tcl -tclargs <routed.dcp> <out.bit>
# Programming: openFPGALoader --cable ft232 --freq 3000000 --fpga-part xcku5p-ffvb676 -f --verify --unprotect-flash <out.bit>
# 3-byte addressing: the probed flash is 128 Mb (docs/validation/flash-boot.md) and the image is under 16 MiB.
if {$argc != 2} { error "usage: -tclargs <routed.dcp> <out.bit>" }
lassign $argv dcp out
open_checkpoint $dcp
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
write_bitstream -force $out
