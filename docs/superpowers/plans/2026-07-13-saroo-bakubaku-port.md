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
- [x] MCU host tests、FPGA iverilog、Phase-1 trampoline 构建通过。
- [ ] 用 ARMCLANG/Keil 完整构建 MCU firmware。
- [ ] 用 SH-2 工具链完整构建 Saturn menu firmware（当前本机 GNU 工程有既有
      assembler 配置错误，与本次 C 改动无关）。
- [ ] Quartus 综合、烧写和真机 magenta/heartbeat 验证。

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
- [x] 当前组合 image SHA-1：
  `fb4a533b3f1821305fa4f453cf31332d9f8e318b`。
- [ ] 把其余 8 个运行期 clean-HLE 服务改写为 native SH-2。
- [ ] clean 重写 HWRAM resident/向量/派发层并完成冷启动交接态。
- [ ] Quartus/Keil 构建并在现有 SAROO 真机验证 overlay 关闭与 heartbeat。

## 第一真机验收步骤

1. Keil 构建并刷入 MCU firmware；Quartus 构建并刷入 FPGA。
2. 构建 `stv-trampoline/trampoline.bin`，复制到
   `/SAROO/STV/trampoline.bin`。
3. 启动 SAROO 菜单，选择“运行 ST-V 镜像”。
4. 确认装载成功日志包含 size、SDRAM base `0x00400000`、ROM base `4MB`。
5. SMPC reset 后应由 Saturn IPL 从 CS0 启动并显示 magenta 背景；HWRAM
   `0x06000000` heartbeat 应为 `0x5AA5A55A`。
