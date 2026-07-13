# Baku Baku → SAROO 单游戏垂直移植计划

**日期：** 2026-07-13  
**工作分支：** `saroo-port-bakubaku`

## 原则

先闭合 Baku Baku 的单游戏路径，再抽象多游戏框架。第一条真机链只要求：
菜单装载一个 Saturn boot image、FPGA 从 CS0 供数、SMPC reset 后 trampoline
显示 heartbeat。CS1/CS2、EEPROM 和完整 IOGA 暂不进入关键路径。

## 里程碑

1. **Phase-1 真机链**：32 MB streaming loader、ST-V 菜单、CS0 ROM 映射、
   magenta trampoline。退出条件是冷/热启动后稳定显示 heartbeat。
2. **Baku pack + boot overlay**：按 Yabause oracle 拼装 32 MB image，FPGA
   用可关闭 overlay 给 Saturn IPL 提供 header，关闭后恢复原始 FPR。
3. **Clean boot trampoline**：构造 HWRAM、向量、工作区和硬件状态，不灌 attract
   快照，不使用 frame-120 的低 BIOS 返回链。
4. **SH-2 native HLE**：把已验证的 clean HLE 放入 CS0 `0x03400000+`，重定向
   resident slots 和两个 Baku game veneer。
5. **最小 IOGA + 输入**：先 ready/idle，再接 Saturn pad → coin/start/JAMMA。
6. **稳定性**：title、投币、实际游戏、连续 3600 帧；随后再做多游戏抽象。

## 第一迭代实现状态

- [x] MCU loader 从单次 2 MB 读取改为 64 KB 分块、最大 32 MB。
- [x] 补多 chunk、oversize、中途 SDRAM 失败和控制位保留测试。
- [x] 增加 STM32 SDRAM aperture bank `0x32`；解决原 16 MB aperture 回绕。
- [x] 菜单新增 `/SAROO/STV/*.bin` 列表和 load 命令，成功后发 SMPC `SYSRES`。
- [x] 把 `stv_rom.c` / `stv_menu.c` 加入 Keil 工程。
- [x] MCU host tests、FPGA iverilog、Saturn menu、Phase-1 trampoline 构建通过。
- [x] 用 Keil MDK 5.43 / ARMCLANG 6.24 clean rebuild MCU firmware；产物代码
      45,188 bytes，0 errors / 0 warnings。
- [x] 用 GNU SH-2 工具链完整构建 384 KiB Saturn menu firmware；修正工具前缀、
      SH-2 big-endian 汇编参数、启动入口 4-byte 对齐和旧头文件声明冲突。
- [x] Quartus Prime Lite 25.1 完成 Cyclone IV 全综合、Fitter、Assembler、
      TimeQuest 和 JIC 生成；0 errors，最差 setup `+0.402 ns`、hold
      `+0.160 ns`。
- [ ] 烧写和真机 magenta/heartbeat 验证。

## Phase-2 建议内存图

2026-07-13 原理图复核确认 SAROO PCB 未把 Saturn AA24/AA25 接进 FPGA，以下
采用现有硬件可实现的 CS0/CS1 分窗，而不是原计划中不可实现的 32 MB CS0：

| Saturn 地址 | image offset | 内容 |
|---|---:|---|
| `0x02000000–0x02FFFFFF` (CS0) | `0x0000000–0x0FFFFFF` | Baku ROM 低 16 MB |
| `0x04000000–0x043FFFFF` (CS1) | `0x1000000–0x13FFFFF` | Baku MPR4（需 source veneer） |
| `0x04400000–0x0440FFFF` (CS1) | `0x1400000–0x140FFFF` | native HLE |
| `0x04F00000–0x04F00FFF` (CS1) | `0x1F00000–0x1F00FFF` | IPL trampoline 永久 alias |

Saturn IPL 期间把 CS0 低 4 KB 映射到尾部 overlay。trampoline 先跳到
`0x04F00000` 的真实别名，再通过 Saturn 可写控制 latch 关闭 overlay；随后
`0x02000000` 必须重新显示未修改的 ST-V FPR 数据。

运行期 70 秒访问枚举确认只有 long-copy `0x0604AFD4` 与 memmove
`0x06053C98` 两个例程读取原 `0x03000000+` 窗口；native HLE 为两者安装
source `+0x01000000` veneer，详见 address-ceiling recon。

## 第二迭代实现状态

- [x] 原理图确认 AA24/AA25 未接 FPGA，排除错误的 32 MB CS0 假设。
- [x] FPGA 增加 ST-V 专用 CS1 高 16 MB 窗口，MCU 对大 image 自动启用。
- [x] 确定性 Baku packer：大小/SHA-1 校验、MAME 布局、JSON manifest。
- [x] CS0 低 4 KB boot overlay、CS1 永久 alias、Saturn 侧关闭 latch。
- [x] trampoline 跳至 `0x04F00106` 并关闭 overlay 后显示 heartbeat。
- [x] 真实 ROM 生成 32 MB 候选 image。
- [x] 70 秒 twin trace 把 MPR4 重定位收敛到两个 copy veneer。
- [x] 两个 source relocation veneer 合入 192-byte clean native HLE，并在
  模拟 SAROO CS0/CS1 分窗的 twin 中原生执行 70 秒。
- [x] packer 在 image offset `0x1400000` 嵌入 native HLE；trampoline 在
  heartbeat 前调用 `0x04400088` installer。
- [x] 加入完整 crash capture 与 CS2 IOGA shadow 后，当前诊断 image SHA-1：
  `daf3cd2b0e70b9d491be84b418d2ce1ee4f32be5`；cold-run image SHA-1：
  `7f4ad2e17e869fcc289a55dbfeafeb87d5e820fe`。
- [x] native SH-2 已实现 `0x0ECC/0x2C64/0x2CAC/0x372C/0x3E4E/
  0x4596/0x4680`，Yabause SH-2 动态测试 11 项全部通过。
- [x] 固定 service redirect table @ `0x04400700`，构建时校验全部
  original→native 地址对。
- [x] 实现 `0x0EFC` steady-state vblank update；SH-2 动态向量通过。
- [x] 实现 `0x3842` selector 0/10/1/20 native dispatch；selector 0 动态向量
  通过，其他 selector 需要边界回归。
- [x] vblank overflow、selector `0x10/1/0x20` signed/range 边界向量通过。
- [x] 70 秒集成回归把全部 clean-HLE 入口转到 CS1 native 执行；无
  invalid opcode、LOWPC/LOWEDGE 或 unimplemented。
- [x] clean resident 生成向量、服务 veneer、实测 handoff 栈与工作区初值；
  SAROO 等价 CS0/CS1 twin 冷启动连续运行 60 秒，无 low BIOS、异常或非法指令。
- [x] 增加一键虚拟验收：packer、MCU host tests、FPGA iverilog、native HLE、
  诊断/运行 trampoline 可从 Windows 经 WSL 或 Linux 单命令全量重建检查。
- [x] native exception trap 保存完整 SH-2 上下文到 `0x06000B80`，并提供
  `tools/stv/decode_crash.py` 离线解析 PC/PR/SR、R0-R14 和控制寄存器。
- [x] 纠正 IOGA 硬件路由：原 `0x00400000` 无卡槽片选；FPGA/MCU 改用
  CS2 packed port shadow，native VBlank 生成 Baku 的 HWRAM 输入状态。
- [x] native SMPC INTBACK 改为跨 VBlank 非阻塞状态机；Yabause SH-2 smoke
  对 idle 与合成按键（方向/A/B/C/X、Start、Coin）均动态通过。
- [x] 显式 cold hardware baseline：cache purge/off、SCU DMA stop/IMS、VDP1
  reset、实测 VDP2 cycle pattern、Slave SH-2 park；handoff 前才开放 IMS/SR。
- [x] EEPROM 边界闭合：1027 帧唯一 PDR2 访问来自已替换的旧 resident poller，
  Baku 游戏无直接 93C46 运行期依赖；持久化留给需要 PDR 的多游戏层。
- [x] SCSP 68K reset-vector watcher：检测 Baku 新音频向量后，以非阻塞
  SNDOFF→SNDON 重启声音 CPU；动态 smoke 验证 `03/07/06` 三条 SMPC 命令。
- [x] 一键虚拟验收纳入 Saturn menu clean build，并校验 `ramimage.bin` 固定为
  384 KiB；当前可用开源工具覆盖的构建、静态检查和动态模拟均已闭合。
- [x] 安装 Keil MDK 5.43、ARMCLANG 6.24、STM32H7 DFP 与 Quartus Prime Lite
  25.1 Cyclone IV 支持；MCU/FPGA vendor build 均通过并接入一键验收。
- [ ] 真机可用时验证 overlay 关闭、heartbeat、视频/声音和物理手柄。

## 第一真机验收步骤

1. Keil 构建并刷入 MCU firmware；Quartus 构建并刷入 FPGA。
2. SD 卡建立 `/SAROO/STV/`，先复制完整 32 MB 诊断镜像
   `bakubaku-saroo.bin`，不是单独的 `trampoline.bin`。不需要 ST-V BIOS。
3. 启动 SAROO 菜单并选择诊断镜像；日志应包含
   `size=02000000`、SDRAM `00400000`、base `4MB`。
4. SMPC reset 后应显示 magenta；红屏表示 FPR 复制校验失败。调试器可见时，
   `0x06000000=0x5AA5A55A` 是成功 heartbeat。
5. 诊断版通过后，把 `bakubaku-saroo-run.bin` 放入同一目录并运行。它应先建立
   相同的 magenta 诊断状态，随后离开诊断停机并进入游戏。
6. 若 run 版失败，保留屏幕表现、串口日志和 master SH-2 寄存器；立即回测诊断版，
   以区分固件/SDRAM 回归与 game-handoff 问题。

两份镜像均不包含、也不要求 `stv-jp-20091.bin`。Saturn 主板自带 BIOS 只负责
识别 cart header；ST-V 运行期依赖由 clean resident/native HLE 提供。
