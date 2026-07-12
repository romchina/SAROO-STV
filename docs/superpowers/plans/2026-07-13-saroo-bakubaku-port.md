# Baku Baku → SAROO 单游戏垂直移植计划

**日期：** 2026-07-13  
**工作分支：** `saroo-port-bakubaku`

## 原则

先闭合 Baku Baku 的 CS0-only 路径，再抽象多游戏框架。第一条真机链只要求：
菜单装载一个 Saturn boot image、FPGA 从 CS0 供数、SMPC reset 后 trampoline
显示 heartbeat。CS1/CS2、EEPROM 和完整 IOGA 暂不进入关键路径。

## 里程碑

1. **Phase-1 真机链**：32 MB streaming loader、ST-V 菜单、CS0 ROM 映射、
   magenta trampoline。退出条件是冷/热启动后稳定显示 heartbeat。
2. **Baku CS0 pack + boot overlay**：按 Yabause oracle 拼装 32 MB image，FPGA
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
- [x] MCU host tests、FPGA iverilog、Phase-1 trampoline 构建通过。
- [ ] 用 ARMCLANG/Keil 完整构建 MCU firmware。
- [ ] 用 SH-2 工具链完整构建 Saturn menu firmware（当前本机 GNU 工程有既有
      assembler 配置错误，与本次 C 改动无关）。
- [ ] Quartus 综合、烧写和真机 magenta/heartbeat 验证。

## Phase-2 建议内存图

| Saturn 地址 | CS0 offset | 内容 |
|---|---:|---|
| `0x02000000–0x033FFFFF` | `0x0000000–0x13FFFFF` | Baku ROM |
| `0x03400000–0x0340FFFF` | `0x1400000–0x140FFFF` | native HLE |
| `0x03F00000–0x03F00FFF` | `0x1F00000–0x1F00FFF` | IPL overlay/trampoline |

Saturn IPL 期间把 CS0 低 4 KB 映射到尾部 overlay。trampoline 先跳到
`0x03F00000` 的真实别名，再通过 Saturn 可写控制 latch 关闭 overlay；随后
`0x02000000` 必须重新显示未修改的 ST-V FPR 数据。

## 第一真机验收步骤

1. Keil 构建并刷入 MCU firmware；Quartus 构建并刷入 FPGA。
2. 构建 `stv-trampoline/trampoline.bin`，复制到
   `/SAROO/STV/trampoline.bin`。
3. 启动 SAROO 菜单，选择“运行 ST-V 镜像”。
4. 确认装载成功日志包含 size、SDRAM base `0x00400000`、ROM base `4MB`。
5. SMPC reset 后应由 Saturn IPL 从 CS0 启动并显示 magenta 背景；HWRAM
   `0x06000000` heartbeat 应为 `0x5AA5A55A`。

