# ST-V BIOS Boot 期枚举 → Trampoline 规格 (M-HLE-3 第二步)

**日期:** 2026-06-28。平台: Yabause twin from-scratch boot。WSL HEAD(+handoff probe)。
配套: [运行期依赖枚举](2026-06-28-stv-bios-runtime-dependency-enumeration.md)。

## 目的

M-HLE-3 的 trampoline(跑在 Saturn/SAROO 卡上)要复刻 ST-V BIOS 开机做的事, 把游戏带到"可运行交接态"。本文枚举那个交接态 + BIOS 在 HWRAM 留下的常驻组件 = trampoline 工作规格。

## 方法

`STV_HANDOFF` 探针(sh2int.c): 捕获 BIOS ROM(low<0x80000) 第一次跳进游戏码区(≥0x06010000)的瞬间, dump 全 SH-2 寄存器。`STV_DUMPRAM=400` 在 boot 后 dump HWRAM(大端序)→ `stvstate/fs_hwram.bin`, python 分析常驻区结构。

## 交接态机器不变量 (trampoline 最后一步)

第一次 BIOS→game: `BIOS 0x000033A2 → game 0x0601270C` (PR=0x33A6 → 是 **BIOS 调用游戏 init 回调**, 会 RTS 回 BIOS)。

| 寄存器 | 值 | 含义 |
|---|---|---|
| VBR | `0x06000000` | 向量表基址 = HWRAM 常驻区头 |
| SR | `0x000000F0` | IRQ 全屏蔽(boot 期) |
| GBR | `0xFFFFFE00` | 全局基址(指 on-chip 寄存器区) |
| R15(SP) | `0x060FFFF8` | 栈在 HWRAM 顶 |

**重要: boot ≠「BIOS 干完一切再跳游戏」, 而是 BIOS↔游戏回调 ping-pong** —— 游戏镜像里含 BIOS 调的 init 回调(如 0x0601270C), 回调又调 BIOS ROM 例程(0x0601274C→0x4596)。trampoline 必须把 BIOS-resident 派发层建好, 才能驱动这套回调。

## HWRAM 内存布局 (trampoline 必须造出)

| 区间 | 内容 | 来源 |
|---|---|---|
| `0x06000000–0x06000400` | **SH-2 向量表** | BIOS 写 |
| `0x06000300–0x06000A14` | **指针/派发表**(两层桥) | BIOS 写 |
| `0x06000C00–0x06003000` | **HWRAM 常驻 BIOS 代码**(派发桩+异常/中断 handler, ~12KB SH-2 码) | BIOS 从 ROM 复制 |
| `0x06003000–0x0600F000` | 0 (gap/工作区) | — |
| `0x0600F000+` | **游戏镜像**("SEGA..." 头 @0xF000, 码 @0x06010000+) | 从 CS0 卡 ROM 复制 |

### 向量表 (0x06000000-0x06000400)
全部 reset/异常/中断向量指向 HWRAM 常驻 handler:
```
vec[0..3] reset      = 0x06002052 (trap loop)
vec[4,6,9,10,11] exc = 0x06002056 (异常 handler)
vec[0x40] VBLANK-IN  = 0x06001F48  vec[0x41] VBLANK-OUT = 0x06001F4E
vec[0x42] = 0x06001FF8  vec[0x43] = 0x06001F54  vec[0x44] = 0x06001F5A
```

### 指针/派发表 (两层之间的桥 — 关键!)
```
[0x06000300] = 0x060014A8   [0x06000304] = 0x06001488   (HWRAM 例程)
[0x06000340] = 0x06000C00   [0x06000348] = 0xFFFFFFFC    (派发桩 / sentinel)
[0x06000610] = 0x06000D14   = BIOS 服务派发器(recon: vblank JSR @[0x610])
[0x06000640] = 0x00003744   → 指进 BIOS ROM (0x372C 例程体)
[0x06000644] = 0x06001412   (HWRAM 例程)
中断/服务派发表 @0x06000A00:
  [0xA00] = 0x06015278  游戏 vblank handler
  [0xA04] = 0x060153DE  游戏 handler
  [0xA08/A0C/A10] = 0x000044FC  → 指进 BIOS ROM (ROM 传输例程)
```
**这张表就是两层的接缝**: 表项有的指 HWRAM 常驻码、有的指 BIOS ROM 例程(=8 个 HLE 目标)。trampoline 建好表 + HLE 提供 ROM 例程 = 闭合。

### BIOS 工作变量 (被 HLE 例程读)
`[0x650]`(0x372C/0x3842 索引) `[0x656]`(0x44FC ROM 传输索引) `[0x658]`(0x3E4E 状态字) `[0x65A]`(0x4596 数组基) `[0x758]`(0xEFC vblank 累加器)。boot 后是运行值, 初值需另捕(boot 早期 dump)。

## 精化结论: ST-V BIOS 依赖 = 两份都来自 BIOS ROM

1. **HWRAM 常驻 BIOS 组件**(~12-16KB): 向量表 + 指针表 + 派发桩 + 异常/中断 handler 代码。boot 期由 ST-V BIOS 从 mask ROM 复制进 HWRAM。
2. **低地址 BIOS ROM 例程**: 游戏运行期 JSR 进去的 8 个(见运行期 recon)+ 其 callee。

**真机 SAROO 两份都得由卡提供**(Saturn mask ROM 非 ST-V BIOS)。这就是移植文档 C 模块"最难", 现在被精确 scoped: 不是"整个 ST-V BIOS", 而是 (~12-16KB 常驻 blob) + (8 例程及 callee)。

## Trampoline 工作步骤 (M-HLE-3 实现清单)

1. **造 HWRAM 常驻 BIOS 组件** @0x06000000-0x0600F000: 向量表 + 指针/派发表 + ~12KB 派发/handler 码。**两条路**: (a) 从能跑的 twin boot 提取该区做 blob 烧进卡(简单/最快, 但 BIOS 派生需注意版权); (b) clean 重写这些 handler/派发逻辑(faithful/合法, 工作量大)。
2. **复制游戏镜像** CS0 卡 ROM → 0x0600F000 (机械; recon: fpr[k]→HWRAM[k+0x0600F000])。
3. **初始化硬件寄存器** VDP1/VDP2/SCU/SCSP 到游戏期望态(目标值从 M-HLE-2 MAME 快照: VDP2 TVMD=8001 DISP-on / SCU IMS vblank 解屏蔽 / 等)。
4. **声音 68k free-run** (v3 机制: 主 CPU 写 68k 复位向量后 reset+run 68k)。
5. **设 SH-2 寄存器** VBR=0x06000000 / SR=0xF0 / GBR=0xFFFFFE00 / SP=0x060FFFF8 → 启动游戏 init 序列(随后与常驻派发层 ping-pong)。

## 复现

```bash
cd /root/yabause-stv
DISPLAY=:0 STV_BOOT=1 STV_HANDOFF=1 STV_DUMPRAM=400 \
  timeout 60 ./build/src/gtk/yabause -b bios/stv-jp-20091.bin -a 2>/tmp/handoff.log
# 分析常驻区: scratchpad/analyze_hwram.py 读 stvstate/fs_hwram.bin
```

## 下一步

枚举两步已完成(运行期 8 例程 + boot 期 trampoline 规格)。**可以写 M-HLE-3 计划了**: 里程碑 = ① trampoline 造交接态(改真 Saturn BIOS 启动、丢 -a, twin 上先用「构造」替「-a 加载」验证) ② 逐个 HLE 8 例程 ③ 收敛到无 ST-V-BIOS-`-a` 依赖的 twin = 真机可移植形态。
