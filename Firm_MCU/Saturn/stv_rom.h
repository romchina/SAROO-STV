/*
 * stv_rom — ST-V ROM loader for SAROO-STV.
 *
 * Streams a ROM image (up to one 32 MB CS0 image) from SD in 64 KB chunks,
 * writes it into the SDRAM region reserved
 * for Phase 1+ ST-V use, configures the FPGA's CS0 ROM mode (sets
 * ST-V ROM mode via MCU control bit 11, ss_rom_base via reg 0x30, and maps
 * image bytes 16 MB+ through CS1 when
 * needed because current SAROO PCBs do not route Saturn AA24), then
 * returns an info struct the Saturn-side boot path can inspect.
 *
 * Unit tests live in Firm_MCU/tests/; they compile against stv_rom.c
 * with UNIT_TEST defined to substitute host-friendly shims for FatFS
 * and the STM32 FSMC window.
 */

#ifndef STV_ROM_H
#define STV_ROM_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint32_t sdram_base;   /* byte offset into SDRAM where ROM was loaded */
    uint32_t size;         /* bytes loaded                                */
    uint16_t rom_base_mb;  /* the MB-unit value written to ss_rom_base    */
} stv_rom_info_t;

/* Load a ROM image from `path` into SDRAM and switch FPGA to CS0 ROM mode.
 * Returns 0 on success, negative on error:
 *   -1: file open / read failure
 *   -2: empty/oversize image or SDRAM write failure
 */
int stv_rom_load(const char *path, stv_rom_info_t *out);

/* Restore the FPGA's default CS0 mode (CD-Block / RAM Cart coexistence).
 * Leaves SDRAM contents intact — only clears ROM mode + rom_base. */
void stv_rom_unload(void);

/* For tests and diagnostics. */
uint32_t stv_rom_sdram_reserve_offset(void);
uint32_t stv_rom_sdram_reserve_size(void);

#endif /* STV_ROM_H */
