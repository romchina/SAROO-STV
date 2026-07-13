# SAROO-STV 真机 bring-up 工具

## 1. 准备 SD 卡

以下命令只创建 `/SAROO/STV/`，复制两份完整 32 MB 镜像、JSON manifest，
并写入 SHA-256 清单；不会修改 SAROO 菜单或其他目录：

```powershell
.\tools\stv\prepare_sd.ps1 -SdRoot E:\
```

先运行 `bakubaku-saroo.bin`。洋红画面和 HWRAM heartbeat
`0x06000000 = 0x5AA5A55A` 通过后，再运行 `bakubaku-saroo-run.bin`。
两份镜像都不需要 ST-V BIOS。

## 2. STM32 烧写与串口

J-Link 通过 SWD 烧写 MCU：

```powershell
.\tools\stv\flash_mcu.ps1
```

脚本使用 `STM32H750VB`、SWD 4 MHz，并将 `ssmaster.bin` 写到
`0x08000000`。调试接头的物理针序必须按 PCB 标记或万用表确认；已确认的网络是
`SWIO`、`SWCK`、`DEBUG_RX`、`DEBUG_TX` 和地，不能根据连接器外形猜针号。

使用 3.3 V USB-TTL（禁止 5 V TTL）采集 MCU 串口：

```powershell
.\tools\stv\capture_uart.ps1 -Port COM5
```

默认参数为 1,000,000 baud、8N1，并在当前目录保存带时间戳的日志。

## 3. FPGA 烧写

USB-Blaster 持久化写入 JIC：

```powershell
.\tools\stv\flash_fpga.ps1
```

只做断电即失的 SOF 验证：

```powershell
.\tools\stv\flash_fpga.ps1 -Volatile `
  -Image .\FPGA\output_files\SSMaster.sof
```

用 `quartus_pgm --list` 确认 cable 编号；不是 `1` 时传 `-Cable`。

## 4. 崩溃边界

native SH-2 异常处理器把完整上下文保存到 Saturn HWRAM
`0x06000B80`。取得 HWRAM dump 后可运行：

```powershell
python .\tools\stv\decode_crash.py hwram.bin
```

J-Link 连接的是 STM32，不能直接读取 Saturn 内部 HWRAM，所以不能用 J-Link
Commander 直接 `savebin 0x06000B80`。首轮 bring-up 应同时保留屏幕表现、UART
日志和 FPGA SignalTap 波形；后续若要自动取 crash record，需要再增加
Saturn→FPGA/MCU crash mailbox。

## 5. SignalTap 调试版本

正式 QSF 保持 `ENABLE_SIGNALTAP OFF`，避免调试逻辑改变发布位流。真机出现
A-Bus/SDRAM 问题时，在 Quartus Signal Tap GUI 中新建 `stv_debug.stp`，以
`mclk` 为采样时钟，优先加入以下 post-fit nodes：

- `SS_CS0`、`SS_CS1`、`SS_CS2`、`SS_RD`、`SS_WR0`、`SS_WR1`；
- `SS_ADDR[*]`、`SS_DATA[*]`、`SS_WAIT`；
- `st_reg_ctrl[*]`、`ss_rom_base[*]`、`st_sdram_bank[*]`；
- `st_boot_overlay`、`ss_boot_overlay_hit`；
- `ss_ram_cs`、`ss_ram_addr[*]`、`st_ram_cs`、`st_ram_addr[*]`；
- `st_ioga_ab[*]`、`st_ioga_ce[*]`、`st_ioga_fd[*]`、`st_ioga_gm[*]`。

触发条件先用 `SS_CS0 == 0 && SS_RD == 0` 捕获 IPL 首次读取；overlay 问题则以
`st_boot_overlay` 的下降沿触发。保存 `.stp` 后仅在本地 debug revision 启用并
重新编译，不要把带 SignalTap 的 SOF/JIC 当作发布固件。
