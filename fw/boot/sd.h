/* SPDX-License-Identifier: MIT */
#ifndef SD_H
#define SD_H

#include <stdint.h>

/* SD card in SPI mode over the spi_sifive controller. All functions return 0 on success, a negative
 * value on error. */
int sd_init(void);
int sd_read(uint32_t lba, uint32_t count, void *dst);

/* Boot header in sector 0 (little endian): magic "HGXBOOT\0", entry count, entry address, then
 * {lba, bytes, address} x count. */
#define SD_BOOT_MAGIC0 0x42584748 /* "HGXB" */
#define SD_BOOT_MAGIC1 0x00544f4f /* "OOT\0" */
#define SD_BOOT_MAX_ENTRIES 8

struct sd_boot_entry {
	uint32_t lba;
	uint32_t bytes;
	uint32_t addr;
};

struct sd_boot_header {
	uint32_t magic[2];
	uint32_t count;
	uint32_t entry;
	struct sd_boot_entry e[SD_BOOT_MAX_ENTRIES];
};

/* Load every entry of the header and return the entry address (> 0), or a negative error. */
long sd_boot_load(void);

#endif
