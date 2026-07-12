/* ST-V image list/load commands exposed to the Saturn boot menu. */

#include "main.h"
#include "ff.h"
#include "cdc.h"
#include "stv_rom.h"

#include <stdlib.h>
#include <string.h>

static int stv_total;
static int *stv_path_offsets = (int *)(IMGINFO_ADDR + 4);
static char *stv_path_buffer = (char *)IMGINFO_ADDR;
static int stv_path_cursor;

static int has_bin_extension(const char *name)
{
    const char *extension = strrchr(name, '.');
    if(extension == NULL)
        return 0;
    return strcasecmp(extension, ".bin") == 0;
}

int list_stv(int show)
{
    FRESULT result;
    DIR directory;
    FILINFO *info;

    stv_total = 0;
    stv_path_cursor = 0x1000;
    memset(stv_path_offsets, 0, 0x20000 - 4);
    *(int *)IMGINFO_ADDR = 0;
    memset(&directory, 0, sizeof(directory));

    result = f_opendir(&directory, "/SAROO/STV");
    if(result != FR_OK)
        return -1;

    info = malloc(sizeof(*info));
    if(info == NULL) {
        f_closedir(&directory);
        return -2;
    }
    memset(info, 0, sizeof(*info));

    while(stv_total < MAX_FILES) {
        int required;
        result = f_readdir(&directory, info);
        if(result != FR_OK || info->fname[0] == 0)
            break;
        if(info->fname[0] == '.' || (info->fattrib & AM_DIR) ||
           !has_bin_extension(info->fname))
            continue;

        required = 11 + strlen(info->fname) + 1;
        if(stv_path_cursor + required >= 0x20000)
            break;
        stv_path_offsets[stv_total] = stv_path_cursor;
        sprintk(stv_path_buffer + stv_path_cursor,
                "/SAROO/STV/%s", info->fname);
        stv_path_cursor += required;
        stv_total++;
        *(int *)IMGINFO_ADDR = stv_total;
    }

    f_closedir(&directory);
    free(info);

    printk("Total ST-V images: %d\n", stv_total);
    if(show) {
        int i;
        for(i = 0; i < stv_total; i++)
            printk(" %2d:  %s\n", i,
                   stv_path_buffer + stv_path_offsets[i]);
        printk("\n");
    }
    return result == FR_OK ? 0 : -1;
}

int load_stv(int index)
{
    stv_rom_info_t info;
    int result;

    if(index < 0 || index >= stv_total || stv_path_offsets[index] == 0) {
        printk("Invalid ST-V image index %d\n", index);
        return -1;
    }

    printk("Load ST-V image: {%s}\n",
           stv_path_buffer + stv_path_offsets[index]);
    result = stv_rom_load(stv_path_buffer + stv_path_offsets[index], &info);
    if(result == 0) {
        printk("ST-V image ready: size=%08x sdram=%08x base=%dMB\n",
               info.size, info.sdram_base, info.rom_base_mb);
    } else {
        printk("ST-V image load failed: %d\n", result);
    }
    return result;
}
