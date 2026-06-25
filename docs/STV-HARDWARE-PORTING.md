# 从 Yabause 软件孪生 到 真机 SAROO：改造清单

本文把 Yabause 软件孪生（[STV-ROADMAP.md](STV-ROADMAP.md) 的验证平台）上摸清的一切，翻译成**真机 SAROO 硬件**上跑 ST-V 游戏所需的改造，并对照 roadmap 的 Phase 划分。

> 前置阅读：[STV-ROADMAP.md](STV-ROADMAP.md)（Phase 0-5）、[superpowers/recon/2026-06-25-stv-bios-hle-recon.md](superpowers/recon/2026-06-25-stv-bios-hle-recon.md)（逆向全过程）。

---

## 0. 关键前提：孪生的跑法在真机上不成立

孪生（Yabause）现在能跑 bakubaku，靠两个**真机做不到**的手段：

| 孪生手段 | 真机为何不行 |
|---|---|
| `--stvboot` 灌 MAME 捕获的 RAM 快照 | 真机没法注入 RAM 状态 |
| `-a` 把 **ST-V BIOS 当 Saturn BIOS 加载**（`-b stv-jp-20091.bin`）| 真机 Saturn 的 BIOS 在主板 mask ROM 里，卡槽（A-Bus）改不了它 |

**孪生证明的是**：ST-V 游戏码能在 Saturn 硅片上正确执行与渲染（二进制兼容，已视觉验证——完整 attract + 从头 boot 的 SEGA WARNING 屏）。
**孪生没证明、也无法直接移植的是**：让 stock Saturn「启动 ST-V BIOS」这条路——它在真机上是死路。

### 真机唯一可行的路

```
Saturn 上电 → 跑自己的 mask BIOS → IPL 引导 SAROO 卡
   → 卡上 trampoline（跑在 Saturn 上）复刻 ST-V BIOS 的游戏初始化
   → 跳进 ST-V 游戏码
   → 游戏运行，调用的 ST-V BIOS 例程由 trampoline/固件 HLE，I/O 由 FPGA 仿真
```

即：**用「计算式构造」replace 孪生的「快照复现」**（roadmap 里的 M-HLE-3）。

---

## 1. 改造模块总览

| 模块 | 孪生里怎么做的 | 真机要做什么 | 对应 Phase |
|---|---|---|---|
| **A. ROM 映射** | `cs0.c` 的 `CART_STV` 把 bakubaku 映进 CS0 | FPGA 把 ST-V 卡带 ROM 映进 A-Bus CS0/CS1/CS2（49MB） | Phase 1-2 |
| **B. Boot trampoline** | （孪生用 BIOS/快照绕过） | Saturn 卡头 + 复刻 ST-V BIOS 的游戏初始化代码 | Phase 1-2（新） |
| **C. ST-V BIOS 例程 HLE** ⚠️ | 把 ST-V BIOS ROM 整个塞 0x00000000 当脚手架 | **HLE 游戏调用的 BIOS 例程**（Saturn mask BIOS 占着地址改不了） | Phase 2 / M-HLE-3 |
| **D. 315-5649 IOGA** | `memory.c` shim `IOGA[7]=0xFC` 等 | FPGA 把 IOGA I/O 芯片做出来 | Phase 3 |
| **E. SMPC / 输入翻译** | shim `PDR=0x7F`、`SYSRES=复位` | STM32 读 Saturn 手柄→翻译成 JAMMA→喂 FPGA IOGA | Phase 3 |
| **F. EEPROM** | （未涉及） | FPGA 仿 93C46，存档到 SD | Phase 4 |

---

## 2. 逐模块详解

### A. ROM 映射（FPGA）— Phase 1-2
- 孪生：`cs0.c:CART_STV` + `StvLoadRoms()` 把 MAME 格式 IC 文件按 ST-V 地址图拼进 CS0。
- 真机：FPGA 把 SDRAM 当 ROM 映射模式供数到 CS0（`0x02000000`）、CS1（`0x04000000`）、CS2（`0x05800000`），只读、满足 A-Bus 时序。STM32 从 SD 卡读 ROM 装进 SDRAM。
- **复用 SAROO 现有能力**：RAM Cart 的 SDRAM→CS0 映射、FatFS 读卡、STM32→FPGA 控制寄存器。

### B. Boot Trampoline（新写，跑在 Saturn 上）— Phase 1-2
真机没有「ST-V BIOS 引导」，所以 ST-V BIOS 开机做的事，要由一段 Saturn 可引导的 trampoline 重做：
1. **Saturn 卡头**：让 Saturn IPL 认出魔数并引导（孪生的 recon 里有 IPL 校验风险记录）。
2. **复刻 ST-V BIOS 初始化**（= 孪生 from-scratch boot 里看到的那串）：
   - 内存清零（孪生见 0xD04 的 `MOV.L R4,@R3;DT;BF/S`）
   - VDP1/VDP2/SCU/SCSP 初始化到游戏期望的状态（孪生捕获过 vdp2reg/scureg/vdp1 等寄存器，可作为目标值参考）
   - **DISP 打开**：孪生证实 DISP-off 纯属中途起跑产物——trampoline 从头跑就自然把 DISP 开好（孪生 from-scratch boot 的 WARNING 屏 `TVMD=8001`，无需 FORCE_DISP）
   - 把游戏码从 CS0 ROM 搬进 HWRAM（孪生 recon：`fpr[k]→HWRAM[k+0x0600F000]`）
   - 设好 SH-2 寄存器，跳游戏入口
3. **这就是 M-HLE-3 的核心**：把孪生的快照换成 trampoline 计算式构造同样的交接态。

### C. ST-V BIOS 运行期例程 HLE ⚠️ 最难
- 孪生把 ST-V BIOS ROM 塞 `0x00000000` 当**运行期服务脚手架**，游戏 JSR 进低地址就有真 ST-V BIOS 码。
- 真机 `0x00000000` 是 **Saturn 自己的 mask BIOS，改不了**（不在 A-Bus 卡槽，是主板内部 ROM）。游戏运行时会调 ST-V BIOS 例程（孪生**已枚举出调用链**：`0x06000D14 → 0x000010E8(=0x00000EFC) / 0x06002098 / 0x06001988 / 0x060014FE`），这些低地址在真 Saturn 上是 Saturn BIOS 的不同代码 → 崩。
- **必须二选一**：
  - (a) **HLE**：手写这些 ST-V BIOS 例程的等价实现，放进卡/RAM，并 patch 游戏的调用点重定向；或
  - (b) **重定位**：trampoline 把需要的 ST-V BIOS 例程 copy 进一段 RAM/卡区，把游戏里对低地址的调用 patch 成指向那段。
- **孪生的最大价值**：它能在能跑的环境里**精确枚举游戏到底调了哪些 ST-V BIOS 例程**，逐个 HLE 即可，不用盲猜整个 BIOS。

### D. 315-5649 IOGA（FPGA）— Phase 3
- 孪生：`memory.c` 在 page `0x040`（`0x00400000`）挂 idle stub，from-scratch boot 把 `IOGA[0x07]` shim 成 `0xFC`（bit0-1 清 = ready 握手）。
- 真机：IOGA 不存在，**FPGA 要在 A-Bus 上响应 `0x00400000` 区**，实现 315-5649 的十几个寄存器（抄 MAME `stv.cpp` / `315_5649.cpp`）：ready 状态位、输入端口、投币、test/service。

### E. SMPC / 输入翻译 — Phase 3
- 孪生 shim 了两处 SMPC：`SYSRES(0x0D)=复位 master SH2`、`PDR1/PDR2 读=0x7F`。
- 真机：Saturn **有自己的 SMPC**（SYSRES 等原生），但 **ST-V 游戏要的是 ST-V JAMMA I/O**（投币/test/service/摇杆），Saturn SMPC 读的是 Saturn 手柄。
- **STM32 固件**：读 Saturn 手柄状态 → 翻译成 JAMMA 位布局 → 写进 FPGA 的 IOGA 仿冒寄存器（D 模块）。Saturn 侧菜单加输入映射（如 Start→投币）。
- 注：孪生那两个 SMPC shim 主要是「跑 ST-V BIOS 引导」时才需要——真机走 trampoline 不跑 ST-V BIOS 引导，故 SYSRES shim 大概率不需要；但 PDR/端口的「ST-V idle 值」可能仍要靠 IOGA/固件呈现。

### F. EEPROM — Phase 4
- 仿 93C46（3 线串行，FPGA 状态机），每游戏一个 `.eeprom` 文件存 SD。

---

## 3. 孪生 → 真机 一句话对照

| 孪生做的 | 真机 SAROO 要做的 |
|---|---|
| 灌快照 / 跑 ST-V BIOS（`--stvboot` / `-a`） | ❌ 都不行 |
| `cs0.c` CART_STV ROM 映射 | → FPGA ROM 映射（A） |
| `IOGA[7]=0xFC` 等 shim | → FPGA 做出 315-5649（D） |
| ST-V BIOS ROM 当脚手架 | → **HLE 那几个被调的 BIOS 例程**（C，最难） |
| SMPC `PDR=0x7F` shim | → STM32 读 Saturn 手柄翻译成 JAMMA（E） |
| 快照交接态 | → trampoline 计算式复刻 BIOS 初始化（B） |

---

## 4. 建议的真机推进顺序

1. **Phase 1**：FPGA ROM 模式（CS0）+ Saturn 卡头 trampoline，先打印 "hello" + ROM dump（不要求游戏跑）。
2. **Phase 2**：49MB 映射 + trampoline 复刻 ST-V BIOS 初始化（B）+ 第一批 BIOS 例程 HLE（C），目标跑到 attract 不崩。
3. **Phase 3**：FPGA IOGA（D）+ SMPC→JAMMA 输入（E），目标能投币进游戏。
4. **Phase 4-5**：EEPROM + 逐游戏兼容。

**孪生持续作为 oracle**：每加一个真机模块，先在 Yabause 孪生上验证对应行为（孪生已能跑到 attract / 从头 boot 到 WARNING 屏，是现成的对照真值）。
