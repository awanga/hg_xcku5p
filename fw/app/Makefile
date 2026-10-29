# SPDX-License-Identifier: MIT
# Loadable programs (linked at 0x40100000 by app.ld). Output: $(BUILD)/<name>.bin
TC ?= $(abspath ../../build/tools/xpack-riscv-none-elf-gcc-15.2.0-1)
CROSS ?= $(TC)/bin/riscv-none-elf-
WERROR ?= -Werror
BUILD ?= build
CFLAGS = -std=c99 -Os -Wall -Wextra $(WERROR) -Wshadow -Wstrict-prototypes -Wdouble-promotion -march=rv64ima_zicsr_zifencei \
	 -mabi=lp64 -mcmodel=medany -ffreestanding -fno-pic
LDFLAGS = -nostdlib -nostartfiles -Wl,--gc-sections -T app.ld

all: $(BUILD)/hello.bin

$(BUILD)/%.elf: %.c ../common/crt0.S app.ld
	mkdir -p $(BUILD)
	$(CROSS)gcc $(CFLAGS) $(LDFLAGS) ../common/crt0.S $< -o $@ -lgcc

$(BUILD)/%.bin: $(BUILD)/%.elf
	$(CROSS)objcopy -O binary $< $@

clean:
	rm -rf build

.PHONY: all clean
