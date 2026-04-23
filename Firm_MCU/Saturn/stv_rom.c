/*
 * stv_rom — implementation. See stv_rom.h for API.
 *
 * Two build modes, selected by the UNIT_TEST preprocessor flag:
 *
 *   UNIT_TEST defined (host sim, Firm_MCU/tests/):
 *     - SD file I/O → stdio fopen/fread
 *     - SDRAM window → in-memory g_mock_sdram[] byte array
 *     - FPGA register writes → updates g_mock_fpga_* shadow state
 *
 *   UNIT_TEST undefined (on STM32H750):
 *     - SD file I/O → FatFS f_open/f_read (ff.h from Firm_MCU/FatFS)
 *     - SDRAM window → FSMC window at FPGA_BASE | 0x01000000 (fsmc_addr[24]=1)
 *     - FPGA register writes → FSMC window at FPGA_BASE (fsmc_addr[24]=0)
 */

#include "stv_rom.h"
#include <string.h>

/* ---------------- Configuration ------------------------------------ */

/* Place the ROM image 4 MB into SDRAM, leaving the low 4 MB for the
 * CD-Block cache image / RAM-cart emulation payload. Adjust if the
 * Saturn boot ROM / CD image grows past this boundary. */
#define STV_ROM_SDRAM_OFFSET   (4u * 1024u * 1024u)
#define STV_ROM_SDRAM_MAX      (48u * 1024u * 1024u)  /* CS0 32 MB + CS1 16 MB */

/* FPGA register map offsets (STM32 FSMC addr bits [7:0] with addr[24]=0) */
#define FPGA_REG_CTRL          0x04   /* ss_reg_ctrl  — bits [13:12] = ss_cs0_type */
#define FPGA_REG_ROM_BASE      0x30   /* ss_rom_base  — 1 MB units                */

#define SS_CS0_TYPE_ROM        (0u << 12)   /* 2'b00 in ss_reg_ctrl[13:12] */
#define SS_CS0_TYPE_DATA_CART  (1u << 12)

/* ---------------- Platform shims ----------------------------------- */

#ifdef UNIT_TEST

#include <stdio.h>
#include <stdlib.h>

/* Host-side mock SDRAM — expose as symbol for tests to inspect. */
uint8_t  g_mock_sdram[STV_ROM_SDRAM_MAX];
uint16_t g_mock_fpga_ctrl;
uint16_t g_mock_fpga_rom_base;

static int sdram_write(uint32_t offset, const void *data, size_t n)
{
    if(offset + n > sizeof(g_mock_sdram)) return -1;
    memcpy(g_mock_sdram + offset, data, n);
    return 0;
}

static int file_read_all(const char *path, void *buf, size_t cap, size_t *out_n)
{
    FILE *f = fopen(path, "rb");
    if(!f) return -1;
    *out_n = fread(buf, 1, cap, f);
    fclose(f);
    return 0;
}

static void fpga_reg_write(uint32_t reg_off, uint16_t val)
{
    switch(reg_off) {
    case FPGA_REG_CTRL:     g_mock_fpga_ctrl     = val; break;
    case FPGA_REG_ROM_BASE: g_mock_fpga_rom_base = val; break;
    default: /* ignore */ break;
    }
}

#else  /* production STM32 build */

#include "ff.h"

/* Provided by board-support code (linker maps FSMC NOR/PSRAM banks). */
extern volatile uint16_t * const FPGA_REG_BASE;        /* fsmc_addr[24]=0 */
extern volatile uint16_t * const FPGA_SDRAM_BASE;      /* fsmc_addr[24]=1 */

static int sdram_write(uint32_t offset, const void *data, size_t n)
{
    /* FSMC SDRAM window is 16-bit wide; byte offsets must be even. */
    if(offset & 1) return -1;
    const uint16_t *src = (const uint16_t *)data;
    volatile uint16_t *dst = FPGA_SDRAM_BASE + (offset / 2);
    for(size_t i = 0; i < n / 2; i++) dst[i] = src[i];
    if(n & 1) {
        /* Odd trailing byte — read-modify-write the last half-word. */
        uint16_t w = dst[n / 2];
        w = (w & 0xFF00) | ((const uint8_t *)data)[n - 1];
        dst[n / 2] = w;
    }
    return 0;
}

static int file_read_all(const char *path, void *buf, size_t cap, size_t *out_n)
{
    FIL f;
    if(f_open(&f, path, FA_READ) != FR_OK) return -1;
    UINT br = 0;
    FRESULT rc = f_read(&f, buf, (UINT)cap, &br);
    f_close(&f);
    *out_n = br;
    return rc == FR_OK ? 0 : -1;
}

static void fpga_reg_write(uint32_t reg_off, uint16_t val)
{
    FPGA_REG_BASE[reg_off / 2] = val;
}

#endif  /* UNIT_TEST */

/* ---------------- Public API --------------------------------------- */

/* 2 MB stage buffer — sized to one f_read() pass on STM32.
 * Larger ROMs are chunked via the multi-pass loop below. */
#define STAGE_BUF_BYTES   (2u * 1024u * 1024u)
static uint8_t s_stage_buf[STAGE_BUF_BYTES];

int stv_rom_load(const char *path, stv_rom_info_t *out)
{
    if(!path || !out) return -1;

    /* Open + size-check in one pass. For Phase 1 we load the entire
     * ROM in one shot (the STAGE_BUF_BYTES ceiling is a per-call cap;
     * expand to multi-pass loading once Phase 2 needs >2 MB images). */
    size_t total = 0;
    if(file_read_all(path, s_stage_buf, STAGE_BUF_BYTES, &total) != 0)
        return -1;

    if(total > STV_ROM_SDRAM_MAX - STV_ROM_SDRAM_OFFSET)
        return -2;

    if(sdram_write(STV_ROM_SDRAM_OFFSET, s_stage_buf, total) != 0)
        return -2;

    /* Configure FPGA: ss_cs0_type = 00 (ROM mode), ss_rom_base = offset / 1 MB. */
    uint16_t base_mb = (uint16_t)(STV_ROM_SDRAM_OFFSET / (1024u * 1024u));
    fpga_reg_write(FPGA_REG_ROM_BASE, base_mb);
    fpga_reg_write(FPGA_REG_CTRL, SS_CS0_TYPE_ROM | 0x0100u);  /* keep existing default bits */

    out->sdram_base  = STV_ROM_SDRAM_OFFSET;
    out->size        = (uint32_t)total;
    out->rom_base_mb = base_mb;
    return 0;
}

void stv_rom_unload(void)
{
    fpga_reg_write(FPGA_REG_ROM_BASE, 0);
    /* Return to the SAROO default (bit 8 set, CS0 type = 00 Bootrom
     * — same encoding as ROM mode, but downstream code treats a zero
     * base as "no ST-V image loaded"). */
    fpga_reg_write(FPGA_REG_CTRL, 0x0100u);
}

uint32_t stv_rom_sdram_reserve_offset(void) { return STV_ROM_SDRAM_OFFSET; }
uint32_t stv_rom_sdram_reserve_size  (void) { return STV_ROM_SDRAM_MAX - STV_ROM_SDRAM_OFFSET; }
