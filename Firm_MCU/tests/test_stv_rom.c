/*
 * Host-side unit tests for stv_rom.c.
 *
 * Build:  make -C Firm_MCU/tests
 * Run:    ./Firm_MCU/tests/test_stv_rom
 *
 * Exits 0 on success, non-zero with a message on failure.
 */

#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/stat.h>

/* Compile the unit under test in-place. */
#include "../Saturn/stv_rom.c"

extern uint8_t  g_mock_sdram[];
extern uint16_t g_mock_fpga_ctrl;
extern uint16_t g_mock_fpga_rom_base;
extern uint16_t g_mock_fpga_sdram_bank;
extern uint16_t g_mock_fpga_boot_overlay;
extern size_t   g_mock_sdram_fail_at;
extern unsigned g_mock_sdram_write_count;

static void reset_mocks(void)
{
    memset(g_mock_sdram, 0xAA, sizeof(g_mock_sdram) > (48u*1024u*1024u) ? (48u*1024u*1024u) : (48u*1024u*1024u));
    g_mock_fpga_ctrl = 0;
    g_mock_fpga_rom_base = 0;
    g_mock_fpga_sdram_bank = 0;
    g_mock_fpga_boot_overlay = 0;
    g_mock_sdram_fail_at = SIZE_MAX;
    g_mock_sdram_write_count = 0;
}

static void write_tmp(const char *path, const void *data, size_t n)
{
    FILE *f = fopen(path, "wb");
    assert(f && "tmp file open");
    assert(fwrite(data, 1, n, f) == n);
    fclose(f);
}

/* ------------------- Tests -------------------- */

static int fails = 0;

#define ASSERT_EQ_U32(label, actual, expected) do {                              \
    if((uint32_t)(actual) != (uint32_t)(expected)) {                             \
        printf("FAIL %s: got %u, expected %u\n",                                 \
               (label), (unsigned)(actual), (unsigned)(expected));               \
        fails++;                                                                 \
    } else {                                                                     \
        printf("PASS %s\n", (label));                                            \
    }                                                                            \
} while(0)

#define ASSERT_EQ_U16(label, actual, expected) do {                              \
    if((uint16_t)(actual) != (uint16_t)(expected)) {                             \
        printf("FAIL %s: got 0x%04x, expected 0x%04x\n",                         \
               (label), (unsigned)(actual), (unsigned)(expected));               \
        fails++;                                                                 \
    } else {                                                                     \
        printf("PASS %s\n", (label));                                            \
    }                                                                            \
} while(0)

#define ASSERT_MEM_EQ(label, actual, expected, n) do {                           \
    if(memcmp((actual), (expected), (n)) != 0) {                                 \
        printf("FAIL %s: SDRAM contents mismatch\n", (label));                   \
        fails++;                                                                 \
    } else {                                                                     \
        printf("PASS %s\n", (label));                                            \
    }                                                                            \
} while(0)

static void test_small_rom_load(void)
{
    printf("\n== test_small_rom_load ==\n");
    reset_mocks();

    const char magic[] = "SEGA SEGASATURN SAROO-STV-TEST";
    const char *path = "/tmp/saroo_stv_test_small.bin";
    write_tmp(path, magic, sizeof(magic));

    stv_rom_info_t info;
    int rc = stv_rom_load(path, &info);
    ASSERT_EQ_U32("small rc", rc, 0);
    ASSERT_EQ_U32("small size", info.size, sizeof(magic));
    ASSERT_EQ_U32("small base", info.sdram_base, 4u * 1024u * 1024u);
    ASSERT_EQ_U16("small rom_base_mb", info.rom_base_mb, 4);

    /* SDRAM content at reserve offset should equal the file bytes. */
    ASSERT_MEM_EQ("small payload in SDRAM",
                  g_mock_sdram + info.sdram_base, magic, sizeof(magic));

    /* FPGA regs: base=4, MCU-owned ST-V ROM mode bit set. */
    ASSERT_EQ_U16("small fpga rom_base", g_mock_fpga_rom_base, 4);
    ASSERT_EQ_U16("small fpga ctrl",     g_mock_fpga_ctrl, ST_CTRL_STV_ROM);
}

static void test_multi_chunk_rom_load(void)
{
    printf("\n== test_multi_chunk_rom_load ==\n");
    reset_mocks();

    const char *path = "/tmp/saroo_stv_test_multichunk.bin";
    const size_t size = STAGE_BUF_BYTES * 2u + 37u;
    uint8_t *payload = malloc(size);
    assert(payload);
    for(size_t i = 0; i < size; i++)
        payload[i] = (uint8_t)((i * 17u + i / STAGE_BUF_BYTES) & 0xFFu);
    write_tmp(path, payload, size);

    g_mock_fpga_ctrl = 0xF055u;
    stv_rom_info_t info;
    int rc = stv_rom_load(path, &info);

    ASSERT_EQ_U32("multi rc", rc, 0);
    ASSERT_EQ_U32("multi size", info.size, size);
    ASSERT_EQ_U32("multi write count", g_mock_sdram_write_count, 3);
    ASSERT_MEM_EQ("multi payload", g_mock_sdram + info.sdram_base,
                  payload, size);
    ASSERT_EQ_U16("multi ctrl preserves unrelated bits", g_mock_fpga_ctrl,
                  (uint16_t)(0xF055u | ST_CTRL_STV_ROM));

    free(payload);
    remove(path);
}

static void test_oversize_rom_rejected(void)
{
    printf("\n== test_oversize_rom_rejected ==\n");
    reset_mocks();

    const char *path = "/tmp/saroo_stv_test_oversize.bin";
    FILE *f = fopen(path, "wb");
    assert(f);
    assert(fseek(f, (long)STV_ROM_IMAGE_MAX, SEEK_SET) == 0);
    assert(fputc(0xA5, f) != EOF);
    fclose(f);

    stv_rom_info_t info = { 1, 2, 3 };
    int rc = stv_rom_load(path, &info);
    ASSERT_EQ_U32("oversize rc", rc, (uint32_t)-2);
    ASSERT_EQ_U32("oversize performs no writes", g_mock_sdram_write_count, 0);
    ASSERT_EQ_U32("oversize leaves FPGA base", g_mock_fpga_rom_base, 0);
    ASSERT_EQ_U32("oversize clears output size", info.size, 0);
    remove(path);
}

static void test_sdram_failure_stops_load(void)
{
    printf("\n== test_sdram_failure_stops_load ==\n");
    reset_mocks();

    const char *path = "/tmp/saroo_stv_test_write_failure.bin";
    const size_t size = STAGE_BUF_BYTES * 2u;
    uint8_t *payload = malloc(size);
    assert(payload);
    memset(payload, 0x5A, size);
    write_tmp(path, payload, size);
    free(payload);

    g_mock_fpga_ctrl = 0xA5A5u;
    g_mock_sdram_fail_at = STV_ROM_SDRAM_OFFSET + STAGE_BUF_BYTES;
    stv_rom_info_t info = { 1, 2, 3 };
    int rc = stv_rom_load(path, &info);

    ASSERT_EQ_U32("write failure rc", rc, (uint32_t)-2);
    ASSERT_EQ_U32("write failure attempted two chunks",
                  g_mock_sdram_write_count, 2);
    ASSERT_EQ_U16("write failure does not enable ROM", g_mock_fpga_ctrl,
                  0xA5A5u);
    ASSERT_EQ_U16("write failure leaves base", g_mock_fpga_rom_base, 0);
    ASSERT_EQ_U32("write failure clears output size", info.size, 0);
    remove(path);
}

static void test_load_crosses_16mb_aperture_bank(void)
{
    printf("\n== test_load_crosses_16mb_aperture_bank ==\n");
    reset_mocks();

    const char *path = "/tmp/saroo_stv_test_bank_crossing.bin";
    const size_t size = (16u * 1024u * 1024u) + STAGE_BUF_BYTES;
    FILE *f = fopen(path, "wb");
    assert(f);
    assert(fseek(f, (long)size - 1, SEEK_SET) == 0);
    assert(fputc(0xC7, f) != EOF);
    fclose(f);

    stv_rom_info_t info;
    int rc = stv_rom_load(path, &info);
    ASSERT_EQ_U32("bank crossing rc", rc, 0);
    ASSERT_EQ_U32("bank crossing size", info.size, size);
    ASSERT_EQ_U16("bank crossing selects bank 1",
                  g_mock_fpga_sdram_bank, 1);
    ASSERT_EQ_U16("bank crossing enables ST-V CS1 window",
                  (uint16_t)(g_mock_fpga_ctrl & ST_CTRL_STV_CS1),
                  ST_CTRL_STV_CS1);
    ASSERT_EQ_U32("bank crossing last byte",
                  g_mock_sdram[STV_ROM_SDRAM_OFFSET + size - 1], 0xC7);
    remove(path);
}

static void test_stv_rom_unload_resets_regs(void)
{
    printf("\n== test_stv_rom_unload_resets_regs ==\n");
    reset_mocks();
    g_mock_fpga_ctrl = 0xC055u;
    /* First load, then unload. */
    const char magic[] = "SATURN";
    const char *path = "/tmp/saroo_stv_test_unload.bin";
    write_tmp(path, magic, sizeof(magic));

    stv_rom_info_t info;
    int rc = stv_rom_load(path, &info);
    ASSERT_EQ_U32("pre-unload load rc", rc, 0);
    ASSERT_EQ_U16("pre-unload rom_base", g_mock_fpga_rom_base, 4);

    stv_rom_unload();
    ASSERT_EQ_U16("post-unload rom_base", g_mock_fpga_rom_base, 0);
    ASSERT_EQ_U16("post-unload boot overlay", g_mock_fpga_boot_overlay, 0);
    ASSERT_EQ_U16("post-unload ctrl preserves unrelated bits",
                  g_mock_fpga_ctrl,
                  (uint16_t)(0xC055u & ~(ST_CTRL_STV_ROM | ST_CTRL_STV_CS1)));
}

static void test_embedded_boot_overlay_is_detected(void)
{
    printf("\n== test_embedded_boot_overlay_is_detected ==\n");
    reset_mocks();

    const char *path = "/tmp/saroo_stv_test_overlay.bin";
    FILE *f = fopen(path, "wb");
    assert(f);
    assert(fseek(f, 0x01F00000, SEEK_SET) == 0);
    assert(fwrite("SEGA SEGASATURN ", 1, 16, f) == 16);
    fclose(f);

    stv_rom_info_t info;
    int rc = stv_rom_load(path, &info);
    ASSERT_EQ_U32("overlay load rc", rc, 0);
    ASSERT_EQ_U16("overlay enabled", g_mock_fpga_boot_overlay, 1);
    ASSERT_EQ_U16("overlay image enables CS1", g_mock_fpga_ctrl & ST_CTRL_STV_CS1,
                  ST_CTRL_STV_CS1);
    remove(path);
}

int main(void)
{
    test_small_rom_load();
    test_multi_chunk_rom_load();
    test_stv_rom_unload_resets_regs();
    test_oversize_rom_rejected();
    test_sdram_failure_stops_load();
    test_load_crosses_16mb_aperture_bank();
    test_embedded_boot_overlay_is_detected();

    if(fails) {
        printf("\n%d FAILURES\n", fails);
        return 1;
    }
    printf("\nALL PASS\n");
    return 0;
}
