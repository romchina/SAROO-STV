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
#define STV_ROM_IMAGE_MAX      (32u * 1024u * 1024u)  /* Phase 1: one CS0 image */

/* FPGA register map offsets (STM32 FSMC addr bits [7:0] with addr[24]=0) */
#define FPGA_REG_CTRL          0x04   /* ss_reg_ctrl  — bits [13:12] = ss_cs0_type */
#define FPGA_REG_ROM_BASE      0x30   /* ss_rom_base  — 1 MB units                */
#define FPGA_REG_SDRAM_BANK    0x32   /* STM32 SDRAM aperture, 16 MB units        */

#define SS_CS0_TYPE_ROM        (0u << 12)   /* 2'b00 in ss_reg_ctrl[13:12] */
#define SS_CS0_TYPE_DATA_CART  (1u << 12)

static void fpga_reg_write(uint32_t reg_off, uint16_t val);

/* ---------------- Platform shims ----------------------------------- */

#ifdef UNIT_TEST

#include <stdio.h>
#include <stdlib.h>

/* Host-side mock SDRAM — expose as symbol for tests to inspect. */
uint8_t  g_mock_sdram[STV_ROM_SDRAM_MAX];
uint16_t g_mock_fpga_ctrl;
uint16_t g_mock_fpga_rom_base;
uint16_t g_mock_fpga_sdram_bank;
size_t   g_mock_sdram_fail_at = SIZE_MAX;
unsigned g_mock_sdram_write_count;

typedef FILE *stv_file_t;

static int sdram_write(uint32_t offset, const void *data, size_t n)
{
    g_mock_sdram_write_count++;
    if(offset + n > g_mock_sdram_fail_at) return -1;
    if(offset + n > sizeof(g_mock_sdram)) return -1;
    g_mock_fpga_sdram_bank = (uint16_t)(offset >> 24);
    memcpy(g_mock_sdram + offset, data, n);
    return 0;
}

static int file_open(stv_file_t *file, const char *path, uint32_t *out_size)
{
    FILE *f = fopen(path, "rb");
    if(!f) return -1;
    if(fseek(f, 0, SEEK_END) != 0) { fclose(f); return -1; }
    long size = ftell(f);
    if(size < 0 || (unsigned long)size > UINT32_MAX) {
        fclose(f);
        return -1;
    }
    if(fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -1; }
    *file = f;
    *out_size = (uint32_t)size;
    return 0;
}

static int file_read(stv_file_t *file, void *buf, size_t n, size_t *out_n)
{
    *out_n = fread(buf, 1, n, *file);
    return ferror(*file) ? -1 : 0;
}

static void file_close(stv_file_t *file) { fclose(*file); }

static void fpga_reg_write(uint32_t reg_off, uint16_t val)
{
    switch(reg_off) {
    case FPGA_REG_CTRL:     g_mock_fpga_ctrl     = val; break;
    case FPGA_REG_ROM_BASE: g_mock_fpga_rom_base = val; break;
    case FPGA_REG_SDRAM_BANK: g_mock_fpga_sdram_bank = val; break;
    default: /* ignore */ break;
    }
}

static uint16_t fpga_reg_read(uint32_t reg_off)
{
    switch(reg_off) {
    case FPGA_REG_CTRL:     return g_mock_fpga_ctrl;
    case FPGA_REG_ROM_BASE: return g_mock_fpga_rom_base;
    case FPGA_REG_SDRAM_BANK: return g_mock_fpga_sdram_bank;
    default: return 0;
    }
}

#else  /* production STM32 build */

#include "ff.h"

typedef FIL stv_file_t;

/* STM32 FMC bank used by SAROO. Address bit 24 selects the raw SDRAM
 * aperture instead of the FPGA register aperture. */
#define FPGA_REG_BASE   ((volatile uint16_t *)0x60000000u)
#define FPGA_SDRAM_BASE ((volatile uint16_t *)0x61000000u)

static int sdram_write(uint32_t offset, const void *data, size_t n)
{
    uint32_t window_offset;

    /* FSMC SDRAM window is 16-bit wide; byte offsets must be even. */
    if(offset & 1) return -1;
    if((offset >> 24) > 3u ||
       (offset & 0x00FFFFFFu) + n > 0x01000000u)
        return -1;
    fpga_reg_write(FPGA_REG_SDRAM_BANK, (uint16_t)(offset >> 24));
    window_offset = offset & 0x00FFFFFFu;
    const uint16_t *src = (const uint16_t *)data;
    volatile uint16_t *dst = FPGA_SDRAM_BASE + (window_offset / 2);
    for(size_t i = 0; i < n / 2; i++) dst[i] = src[i];
    if(n & 1) {
        /* Odd trailing byte — read-modify-write the last half-word. */
        uint16_t w = dst[n / 2];
        w = (w & 0xFF00) | ((const uint8_t *)data)[n - 1];
        dst[n / 2] = w;
    }
    return 0;
}

static int file_open(stv_file_t *file, const char *path, uint32_t *out_size)
{
    if(f_open(file, path, FA_READ) != FR_OK) return -1;
    FSIZE_t size = f_size(file);
    if(size > UINT32_MAX) {
        f_close(file);
        return -1;
    }
    *out_size = (uint32_t)size;
    return 0;
}

static int file_read(stv_file_t *file, void *buf, size_t n, size_t *out_n)
{
    UINT br = 0;
    FRESULT rc = f_read(file, buf, (UINT)n, &br);
    *out_n = br;
    return rc == FR_OK ? 0 : -1;
}

static void file_close(stv_file_t *file) { f_close(file); }

static void fpga_reg_write(uint32_t reg_off, uint16_t val)
{
    FPGA_REG_BASE[reg_off / 2] = val;
}

static uint16_t fpga_reg_read(uint32_t reg_off)
{
    return FPGA_REG_BASE[reg_off / 2];
}

#endif  /* UNIT_TEST */

/* ---------------- Public API --------------------------------------- */

/* Keep the staging buffer small enough for the STM32 image. Full CS0 images
 * are streamed through this buffer and never need to fit in MCU RAM. */
#define STAGE_BUF_BYTES   (64u * 1024u)
static uint8_t s_stage_buf[STAGE_BUF_BYTES] __attribute__((aligned(2)));

int stv_rom_load(const char *path, stv_rom_info_t *out)
{
    stv_file_t file;
    uint32_t file_size;
    uint32_t offset = 0;

    if(!path || !out) return -1;
    memset(out, 0, sizeof(*out));

    if(file_open(&file, path, &file_size) != 0)
        return -1;

    if(file_size == 0 || file_size > STV_ROM_IMAGE_MAX ||
       file_size > STV_ROM_SDRAM_MAX - STV_ROM_SDRAM_OFFSET) {
        file_close(&file);
        return -2;
    }

    while(offset < file_size) {
        size_t want = file_size - offset;
        size_t got = 0;
        if(want > STAGE_BUF_BYTES) want = STAGE_BUF_BYTES;
        if(file_read(&file, s_stage_buf, want, &got) != 0 || got != want) {
            file_close(&file);
            return -1;
        }
        if(sdram_write(STV_ROM_SDRAM_OFFSET + offset,
                       s_stage_buf, got) != 0) {
            file_close(&file);
            return -2;
        }
        offset += (uint32_t)got;
    }
    file_close(&file);

    /* Configure FPGA: ss_cs0_type = 00 (ROM mode), ss_rom_base = offset / 1 MB. */
    uint16_t base_mb = (uint16_t)(STV_ROM_SDRAM_OFFSET / (1024u * 1024u));
    uint16_t ctrl = fpga_reg_read(FPGA_REG_CTRL);
    ctrl = (uint16_t)((ctrl & ~(3u << 12)) | SS_CS0_TYPE_ROM | 0x0100u);
    fpga_reg_write(FPGA_REG_ROM_BASE, base_mb);
    fpga_reg_write(FPGA_REG_CTRL, ctrl);

    out->sdram_base  = STV_ROM_SDRAM_OFFSET;
    out->size        = file_size;
    out->rom_base_mb = base_mb;
    return 0;
}

void stv_rom_unload(void)
{
    uint16_t ctrl = fpga_reg_read(FPGA_REG_CTRL);
    fpga_reg_write(FPGA_REG_ROM_BASE, 0);
    fpga_reg_write(FPGA_REG_SDRAM_BANK, 0);
    /* Return to the SAROO default (bit 8 set, CS0 type = 00 Bootrom
     * — same encoding as ROM mode, but downstream code treats a zero
     * base as "no ST-V image loaded"). */
    ctrl = (uint16_t)((ctrl & ~(3u << 12)) | 0x0100u);
    fpga_reg_write(FPGA_REG_CTRL, ctrl);
}

uint32_t stv_rom_sdram_reserve_offset(void) { return STV_ROM_SDRAM_OFFSET; }
uint32_t stv_rom_sdram_reserve_size  (void) { return STV_ROM_SDRAM_MAX - STV_ROM_SDRAM_OFFSET; }
