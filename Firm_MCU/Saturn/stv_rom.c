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
#define FPGA_REG_CTRL          0x04   /* st_reg_ctrl — MCU-side FPGA control       */
#define FPGA_REG_ROM_BASE      0x30   /* ss_rom_base  — 1 MB units                */
#define FPGA_REG_SDRAM_BANK    0x32   /* STM32 SDRAM aperture, 16 MB units        */
#define FPGA_REG_BOOT_OVERLAY   0x34   /* CS0 low 4 KB -> image offset 31 MB      */
#define FPGA_REG_IOGA_AB        0x36   /* packed active-low ports A/B             */
#define FPGA_REG_IOGA_CE        0x38   /* packed active-low ports C/E             */
#define FPGA_REG_IOGA_FD        0x3A   /* packed active-low ports F/D             */
#define FPGA_REG_IOGA_GM        0x3C   /* packed active-low port G / mode          */

#define ST_CTRL_STV_CS1        (1u << 10)   /* CS1 maps image bytes 16 MB+ */
#define ST_CTRL_STV_ROM        (1u << 11)   /* force CS0/CS1 read-only ROM */

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
uint16_t g_mock_fpga_boot_overlay;
uint16_t g_mock_fpga_ioga_ab;
uint16_t g_mock_fpga_ioga_ce;
uint16_t g_mock_fpga_ioga_fd;
uint16_t g_mock_fpga_ioga_gm;
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
    case FPGA_REG_BOOT_OVERLAY: g_mock_fpga_boot_overlay = val; break;
    case FPGA_REG_IOGA_AB: g_mock_fpga_ioga_ab = val; break;
    case FPGA_REG_IOGA_CE: g_mock_fpga_ioga_ce = val; break;
    case FPGA_REG_IOGA_FD: g_mock_fpga_ioga_fd = val; break;
    case FPGA_REG_IOGA_GM: g_mock_fpga_ioga_gm = val; break;
    default: /* ignore */ break;
    }
}

static uint16_t fpga_reg_read(uint32_t reg_off)
{
    switch(reg_off) {
    case FPGA_REG_CTRL:     return g_mock_fpga_ctrl;
    case FPGA_REG_ROM_BASE: return g_mock_fpga_rom_base;
    case FPGA_REG_SDRAM_BANK: return g_mock_fpga_sdram_bank;
    case FPGA_REG_BOOT_OVERLAY: return g_mock_fpga_boot_overlay;
    case FPGA_REG_IOGA_AB: return g_mock_fpga_ioga_ab;
    case FPGA_REG_IOGA_CE: return g_mock_fpga_ioga_ce;
    case FPGA_REG_IOGA_FD: return g_mock_fpga_ioga_fd;
    case FPGA_REG_IOGA_GM: return g_mock_fpga_ioga_gm;
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

void stv_ioga_set(const stv_ioga_ports_t *ports)
{
    if(!ports) return;
    fpga_reg_write(FPGA_REG_IOGA_AB,
                   (uint16_t)(((uint16_t)ports->a << 8) | ports->b));
    fpga_reg_write(FPGA_REG_IOGA_CE,
                   (uint16_t)(((uint16_t)ports->c << 8) | ports->e));
    fpga_reg_write(FPGA_REG_IOGA_FD,
                   (uint16_t)(((uint16_t)ports->f << 8) | ports->d));
    fpga_reg_write(FPGA_REG_IOGA_GM,
                   (uint16_t)(((uint16_t)ports->g << 8) | ports->mode));
}

void stv_ioga_idle(void)
{
    const stv_ioga_ports_t idle = {
        0xFF, 0xFF, 0xFF, 0xFC, 0xFF, 0xFF, 0xFF, 0x00
    };
    stv_ioga_set(&idle);
}

/* Keep the staging buffer small enough for the STM32 image. Full CS0 images
 * are streamed through this buffer and never need to fit in MCU RAM. */
#define STAGE_BUF_BYTES   (64u * 1024u)
static uint8_t s_stage_buf[STAGE_BUF_BYTES] __attribute__((aligned(2)));

int stv_rom_load(const char *path, stv_rom_info_t *out)
{
    stv_file_t file;
    uint32_t file_size;
    uint32_t offset = 0;
    int has_boot_overlay = 0;
    static const uint8_t saturn_magic[16] = "SEGA SEGASATURN ";

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
        if(offset <= 0x01F00000u && offset + got >= 0x01F00010u &&
           memcmp(s_stage_buf + (0x01F00000u - offset), saturn_magic,
                  sizeof(saturn_magic)) == 0)
            has_boot_overlay = 1;
        if(sdram_write(STV_ROM_SDRAM_OFFSET + offset,
                       s_stage_buf, got) != 0) {
            file_close(&file);
            return -2;
        }
        offset += (uint32_t)got;
    }
    file_close(&file);

    /* Configure the MCU-owned ST-V ROM mode and SDRAM base. */
    uint16_t base_mb = (uint16_t)(STV_ROM_SDRAM_OFFSET / (1024u * 1024u));
    uint16_t ctrl = fpga_reg_read(FPGA_REG_CTRL);
    ctrl |= ST_CTRL_STV_ROM;
    if(file_size > 0x01000000u)
        ctrl |= ST_CTRL_STV_CS1;
    else
        ctrl &= (uint16_t)~ST_CTRL_STV_CS1;
    fpga_reg_write(FPGA_REG_ROM_BASE, base_mb);
    fpga_reg_write(FPGA_REG_BOOT_OVERLAY, (uint16_t)has_boot_overlay);
    stv_ioga_idle();
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
    fpga_reg_write(FPGA_REG_BOOT_OVERLAY, 0);
    stv_ioga_idle();
    /* Return to normal SAROO control without disturbing FIFO/IRQ bits. */
    ctrl &= (uint16_t)~(ST_CTRL_STV_ROM | ST_CTRL_STV_CS1);
    fpga_reg_write(FPGA_REG_CTRL, ctrl);
}

uint32_t stv_rom_sdram_reserve_offset(void) { return STV_ROM_SDRAM_OFFSET; }
uint32_t stv_rom_sdram_reserve_size  (void) { return STV_ROM_SDRAM_MAX - STV_ROM_SDRAM_OFFSET; }
