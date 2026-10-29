# SPDX-License-Identifier: MIT
# Working-set sweep firmware for the L2 study. Two images from one source:
#   $(BUILD)/membench_rom.hex  runs from the boot ROM (simulation sweeps, uses ../boot/boot.ld)
#   $(BUILD)/membench_app.bin  loaded into DDR4 at 0x40100000 with tools/load.py (uses ../app/app.ld)
# make BUILD=build_sim DEFS="-DSIZES=16384,65536 -DMAX_BYTES=65536" builds a short image for simulation.
TC ?= $(abspath ../../build/tools/xpack-riscv-none-elf-gcc-15.2.0-1)
CROSS ?= $(TC)/bin/riscv-none-elf-
WERROR ?= -Werror
ARCH ?= rv64ima_zicsr_zifencei
ABI ?= lp64
BUILD ?= build
DEFS ?=
CFLAGS = -std=c99 -Os -Wall -Wextra $(WERROR) -Wshadow -Wstrict-prototypes -Wdouble-promotion -fstack-usage \
	 -march=$(ARCH) -mabi=$(ABI) -mcmodel=medany -ffreestanding -fno-pic
LDFLAGS = -nostdlib -nostartfiles -Wl,--gc-sections

all: $(BUILD)/membench_rom.hex $(BUILD)/membench_app.bin

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/membench_rom.elf: ../common/crt0.S main.c ../boot/boot.ld | $(BUILD)
	$(CROSS)gcc $(CFLAGS) $(DEFS) $(LDFLAGS) -T ../boot/boot.ld ../common/crt0.S main.c -o $@ -lgcc

$(BUILD)/membench_app.elf: ../common/crt0.S main.c ../app/app.ld | $(BUILD)
	$(CROSS)gcc $(CFLAGS) $(DEFS) $(LDFLAGS) -T ../app/app.ld ../common/crt0.S main.c -o $@ -lgcc

$(BUILD)/membench_app.bin: $(BUILD)/membench_app.elf
	$(CROSS)objcopy -O binary $< $@

$(BUILD)/membench_rom.hex: $(BUILD)/membench_rom.elf
	$(CROSS)objcopy -O binary $< $(BUILD)/membench_rom.bin
	python3 -c "d = open('$(BUILD)/membench_rom.bin','rb').read(); d += bytes(-len(d) % 4); \
	assert len(d) <= 16384, 'ROM image exceeds 16 KiB'; \
	open('$@','w').write(''.join('%08x\n' % int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)) + '00000013\n' * (4096 - len(d)//4))"

clean:
	rm -rf build build_sim build_sweep

.PHONY: all clean
