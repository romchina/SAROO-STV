# SAROO-STV Roadmap — 在真机 Saturn 上跑 ST-V 街机 ROM

**Fork 自**: [tpunix/SAROO](https://github.com/tpunix/SAROO)
**目标**: 在不改 Saturn 主板的前提下，通过 SAROO 卡槽硬件让真 Saturn 启动并运行 ST-V 街机游戏 ROM。

---

## 为什么可行（硬件前提）

Sega ST-V 和 Saturn 的核心硅片几乎一模一样：
- 2× SH-2 @ 28.6 MHz（master/slave）
- 68EC000 声音 CPU @ 11.3 MHz
- SCU、VDP1、VDP2、SCSP、RAM 规格全同
- **CPU 指令、图形命令、声音程序完全二进制兼容**

差异集中在**外设**，具体见下文 Phase 划分。

**Saturn 卡槽 A-Bus 引脚**确认引出 SS_CS0 / SS_CS1 / SS_CS2 三根片选（见 `FPGA/SSMaster.v:87-89`），对应：

| 片选 | Saturn 地址 | 大小 | ST-V 用途 |
|---|---|---|---|
| SS_CS0 | `0x02000000 – 0x03FFFFFF` | 32 MB | 主 ROM（入口 + 代码） |
| SS_CS1 | `0x04000000 – 0x04FFFFFF` | 16 MB | 补充 ROM（图形/音频） |
| SS_CS2 | `0x05800000 – 0x058FFFFF` | 1 MB | 额外 ROM（部分游戏） |

合计 49 MB，覆盖 ST-V 卡带最大容量。

---

## 当前 SAROO 架构复用度

| 现有能力 | Phase 1 复用方式 |
|---|---|
| FPGA SDRAM → CS0 映射（RAM Cart 模式） | 改造为 ROM 映射模式，加只读保护 |
| STM32 SD 卡读取（FatFS） | 读 ST-V ROM 文件替代 CUE/BIN |
| STM32→FPGA 控制寄存器（FSMC 映射 8'h04 起） | 增加 ROM base / mode 控制位 |
| Saturn 侧 Firm_Saturn 菜单固件 | 增加 "Load ST-V ROM" 菜单项 |

**要新写**：CS1 → SDRAM 映射、CS2 分模式切换、315-5649 I/O 仿冒、BIOS HLE、EEPROM 仿冒。

---

## Phase 划分

每个 Phase **交付一个可独立验证的里程碑**。

### Phase 0 — 项目基础设施（本 roadmap + toolchain 确认）
**交付**：
- Fork 建好（✅ `romchina/SAROO-STV`）
- 本 roadmap + Phase 1 详细计划
- Quartus 14.0、MDK5、SH-ELF、iverilog、Mednafen 环境清单与验证脚本

**退出条件**：能编译原版 SAROO 固件（FPGA `.rbf` + STM32 `.bin` + Saturn `.elf`），在真机上跑 Saturn CD 游戏确认硬件基线没坏。

---

### Phase 1 — ROM 映射 + Saturn IPL 引导（"Hello World"）
**详细计划**：`docs/superpowers/plans/2026-04-24-stv-phase1-rom-boot.md`

**交付**：
- FPGA 支持 CS0 "ROM 模式"，从 SDRAM 供数，只读，满足 A-Bus 时序
- STM32 能从 SD 卡 `/SAROO/STV/<gamedir>/` 载入 ROM 文件到 SDRAM
- 一个最小的 Saturn 格式启动 stub（trampoline）放在 ROM base，让 Saturn IPL 认出并启动
- Trampoline 在 VDP2 上打印 "SAROO-STV Phase 1 OK" + ROM 前 256 字节的 hex dump

**验证路径**：
1. FPGA 仿真：iverilog testbench 确认 CS0 读返回正确 SDRAM 数据 + 时序
2. Mednafen 预演：用手工构造的 ROM 镜像（带 Saturn 头的 trampoline + ST-V ROM）跑通
3. 真机：插 SAROO，SD 里放 ST-V ROM，Saturn 开机看到 hello

**退出条件**：真机上能看到 trampoline 画面，SH-2 能读到 ST-V ROM 前 N 字节。**不要求 ST-V 游戏真跑起来**。

---

### Phase 2 — 完整 49MB 映射 + ROM 头补丁 + ST-V BIOS 最小 HLE
**目标**：让无保护、无 JAMMA I/O 依赖的简单 ST-V ROM 跑到"想读手柄但没手柄"那一步。

**任务**：
1. FPGA：CS1 → SDRAM 映射（第二个 32MB 偏移区）；CS2 分模式（CD Block 模式 / ROM 模式切换）
2. STM32：加载 MAME 格式 ROM（多个 IC 文件）按 ST-V 地址图拼装到 SDRAM
3. 动态头部补丁：FPGA 在读 `0x02000000-0x0200000F` 时返回 Saturn 魔数而非 ST-V 魔数（或 trampoline 跳转）
4. ST-V BIOS HLE：把 `0xA0xxxxxx` ST-V BIOS 向量 trap 到 trampoline 里的 stub（空实现或最简单实现）
5. 选一个最简单的 ST-V ROM（如 `sanjeon2`、`astrass` 的简单部分，或 `Finalarch`）逐条调试到崩溃点

**退出条件**：选中的 ST-V ROM 能跑到 attract mode 或首个读输入点，不崩。

---

### Phase 3 — 315-5649 I/O 芯片仿冒 + SMPC→JAMMA 输入翻译
**目标**：游戏可以读到手柄输入、投币、test/service 按钮。

**任务**：
1. 抄 MAME `stv.cpp` 的 315-5649 寄存器实现到 Verilog（寄存器只有十几个，量不大）
2. FPGA 在 A-Bus 上响应 `0x00400001 / 0x00400003 / ...`（需要确认 ST-V 上这地址具体在哪个 CS 区）
3. STM32 通过 SMPC 读 Saturn 手柄状态，翻译成 JAMMA 位布局，写回 FPGA 里的仿冒寄存器
4. 在 Saturn 侧固件里加"输入映射配置"菜单（比如把 Saturn 手柄 Start 映射为 JAMMA 投币）

**退出条件**：能在 `Finalarch` / `Die Hard Arcade` 等游戏里投币进游戏、操作角色。

---

### Phase 4 — EEPROM 仿冒 + 设置持久化
**目标**：游戏的 dip switch / high score / test menu 设置能保存。

**任务**：
1. 仿冒 93C46 EEPROM 协议（3 线串行，FPGA 做状态机）
2. STM32 把 EEPROM 内容映射到 SD 卡上每游戏一个 `.eeprom` 文件
3. 在 Saturn 侧菜单加"EEPROM 重置"、"导出配置"功能

**退出条件**：游戏保存的设置断电不丢失。

---

### Phase 5 — 逐游戏兼容性（长尾）
**目标**：覆盖尽可能多的 ST-V ROM。

**任务**（优先级从易到难）：
1. 无保护游戏：`Die Hard Arcade`, `Sega Rally Championship`, `Golden Axe The Duel`（ST-V 版）等
2. 用简单 ROM banking 的游戏
3. 保护芯片游戏：
   - Radiant Silvergun（Treasure 自定义保护）
   - Decathlete（ROM 压缩解码硬件）
   - Critical Velocity, Astra Superstars, Elan Doree（其他保护）
   - 每款需要单独逆向或抄 MAME 实现

**退出条件**：维护一份 compat list，明示支持 / 部分支持 / 不支持。

---

## 工具链要求

| 工具 | 版本 | 用途 | 备注 |
|---|---|---|---|
| Quartus Prime | 14.0 或 18.1 Lite | FPGA 综合（EP4CE6） | 14.0 是 tpunix 原版，18.1 Lite 免费且仍支持 Cyclone IV |
| iverilog + GTKWave | 最新 | 仿真 SSMaster.v 改动 | 代替商业 ModelSim |
| MDK-ARM（Keil） | MDK5 | STM32H750 固件 | tpunix 原版依赖 |
| SH-ELF GCC | SaturnOrbit 包 | Saturn 侧 `Firm_Saturn` | |
| ngdevkit 或 Yaul | 最新 | 写 trampoline / 测试 ROM | Yaul 对 Saturn 更友好 |
| Mednafen | ≥1.30 | 无硬件预演 ROM 启动 | 比 SAROO 真机调试快 |
| MAME 源码 | 最新 | 抄 ST-V 外设实现（非跑 MAME） | `src/mame/sega/stv*.cpp` |

---

## 风险清单（优先排查的高风险项）

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| A-Bus 时序 FPGA 从 SDRAM 追不上 mask ROM 原生速度 | 中 | 游戏随机崩 | Phase 1 仿真阶段就测 worst-case 访问模式 |
| Saturn IPL 对 cart 头部校验比想象严（多字节魔数、校验和） | 中 | 根本启动不了 | Phase 1 早期用 Mednafen 预演，调明 IPL 源码 |
| 部分 ST-V ROM 对 VDP2 VRAM 布局的初始假设与 Saturn 不同 | 低 | 画面花但不崩 | Phase 2 可接受，单游戏 patch |
| ST-V BIOS 函数调用数量远超预估 | 低 | HLE 工作量膨胀 | MAME `stv.cpp` 的 BIOS 调用 trap 列表有限，先抄 |
| 保护芯片游戏需要精确时序仿真，FPGA 资源吃紧 | 高 | Radiant Silvergun 类游戏永远跑不成 | Phase 5 才触及，可以选择放弃 |
| CS2 被 ROM 模式占用后 CD Block 失能 | 低 | 不能在 ST-V 模式下用 CD | 按设计：启动时选 Saturn-CD 或 ST-V，独占 |

---

## 非目标（Out of Scope）

- 改 Saturn 主板 / 贴片。SAROO 必须保持纯卡槽设备。
- 直接跑未 dump 的 ST-V 卡带。只支持 MAME 格式 ROM dump。
- 网络对战、录像回放、rewind 等模拟器特性。
- 街机柜专用周边（方向盘、枪、控制台）的支持放在 Phase 5 后单独考虑。

---

## 参考资料

- MAME 源码 `src/mame/sega/stv.cpp`, `stvprot.cpp`, `315_5649.cpp`
- ST-V BIOS 反汇编（MAME debugger dump）
- Saturn IPL 反汇编（Charles MacDonald, Antime, Ponut64 的记录）
- [nicole.express: The Solid State Saturn: Sega ST-V!](https://nicole.express/2021/segasonic-the-saturn.html)
- [tpunix/SAROO `doc/SAROO技术点滴.txt`](../doc/SAROO技术点滴.txt)
- [MiSTer FPGA ST-V Core 讨论](https://misterfpga.org/viewtopic.php?t=7586)
- Yaul SDK（Saturn homebrew toolchain）
