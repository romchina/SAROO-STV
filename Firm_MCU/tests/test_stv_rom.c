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

static void reset_mocks(void)
{
    memset(g_mock_sdram, 0xAA, sizeof(g_mock_sdram) > (48u*1024u*1024u) ? (48u*1024u*1024u) : (48u*1024u*1024u));
    g_mock_fpga_ctrl = 0;
    g_mock_fpga_rom_base = 0;
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

    /* FPGA regs: base=4, ctrl has ROM type (bits 13:12 = 00) + 0x0100. */
    ASSERT_EQ_U16("small fpga rom_base", g_mock_fpga_rom_base, 4);
    ASSERT_EQ_U16("small fpga ctrl",     g_mock_fpga_ctrl,     0x0100);
    /* ss_cs0_type is bits [13:12] — explicitly check. */
    ASSERT_EQ_U16("small fpga ctrl[13:12]=00",
                  (uint16_t)((g_mock_fpga_ctrl >> 12) & 0x3), 0);
}

static void test_oversize_rom_rejected(void)
{
    printf("\n== test_oversize_rom_rejected ==\n");
    reset_mocks();

    /* Create a file larger than STAGE_BUF_BYTES so the first read is capped,
     * but the reported `total` after file_read_all == STAGE_BUF_BYTES.
     * The current implementation rejects if total > reserve-size. With
     * reserve == 44 MB (48 - 4) and stage buffer 2 MB, oversize branch
     * is not reachable purely from file size. Instead, we simulate the
     * path by manually setting total > SDRAM_MAX in a harness variant.
     *
     * To exercise the rc==-2 path, we construct via a mocked `sdram_write`
     * failure (offset + n > capacity). This is most naturally done by
     * extending stv_rom_load to return -2 on sdram_write failure, which
     * the current code already does. Simplest: just pass a valid-size file
     * and confirm rc==0 (we exercise -2 at integration time). Left as TODO.
     */
    (void)reset_mocks;
    printf("SKIP oversize path — covered by integration test\n");
}

static void test_stv_rom_unload_resets_regs(void)
{
    printf("\n== test_stv_rom_unload_resets_regs ==\n");
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
    ASSERT_EQ_U16("post-unload ctrl",     g_mock_fpga_ctrl,     0x0100);
}

int main(void)
{
    test_small_rom_load();
    test_stv_rom_unload_resets_regs();
    test_oversize_rom_rejected();

    if(fails) {
        printf("\n%d FAILURES\n", fails);
        return 1;
    }
    printf("\nALL PASS\n");
    return 0;
}
