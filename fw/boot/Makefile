# SPDX-License-Identifier: MIT
# Boot ROM firmware for the minimal SoC. Output: $(BUILD)/boot_rom.hex (32-bit words for $readmemh), $(BUILD)/boot.elf.
# make BUILD=build_sim DEFS=-DTEST_BYTES=65536 builds the short-test image used by the SoC simulation.
BUILD ?= build
DEFS ?=
TC ?= $(abspath ../../build/tools/xpack-riscv-none-elf-gcc-15.2.0-1)
CROSS ?= $(TC)/bin/riscv-none-elf-
WERROR ?= -Werror
ARCH ?= rv64ima_zicsr_zifencei
ABI ?= lp64
CFLAGS = -std=c99 -Os -Wall -Wextra $(WERROR) -Wshadow -Wstrict-prototypes -Wdouble-promotion -fstack-usage \
	 -march=$(ARCH) -mabi=$(ABI) -mcmodel=medany -ffreestanding -fno-pic
LDFLAGS = -nostdlib -nostartfiles -T boot.ld -Wl,--gc-sections

all: $(BUILD)/boot_rom.hex

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/boot.elf: ../common/crt0.S main.c boot.ld | $(BUILD)
	$(CROSS)gcc $(CFLAGS) $(DEFS) $(LDFLAGS) ../common/crt0.S main.c -o $@ -lgcc
	$(CROSS)size $@

$(BUILD)/boot_rom.hex: $(BUILD)/boot.elf
	$(CROSS)objcopy -O binary $< $(BUILD)/boot.bin
	python3 -c "import sys; d = open('$(BUILD)/boot.bin','rb').read(); d += bytes(-len(d) % 4); \
	assert len(d) <= 16384, 'ROM image exceeds 16 KiB'; \
	open('$@','w').write(''.join('%08x\n' % int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)) + '00000013\n' * (4096 - len(d)//4))"

# The image has no host-runnable unit tests; the SoC simulation in tests/soc runs it.
test: all

clean:
	rm -rf build build_sim

.PHONY: all test clean
