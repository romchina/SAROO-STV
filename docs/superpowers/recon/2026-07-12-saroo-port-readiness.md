# Baku Baku clean HLE → SAROO 移植就绪边界

**日期：** 2026-07-12

## 结论

Yabause 软件孪生已在 stock Saturn BIOS 下，用 clean-room HLE 连续运行
BAKU BAKU ANIMAL 到 frame 3600。自动投币/开始可进入实际游戏，棋盘状态持续
推进；全程没有 master SH-2 illegal opcode、低地址 BIOS 执行或未知 HLE 入口。

这满足“开始 SAROO 移植”的 oracle 门槛：游戏运行期所需的 BIOS 行为已经有一套
可重复验证的 C 语义和长跑基线。下一阶段可以把这些语义翻译成 SAROO 上运行的
SH-2 trampoline/HLE；不需要再以“先猜有哪些 BIOS 调用”为前置研究。

## 已闭合的运行期服务

| ST-V BIOS 入口 | clean HLE 语义 |
|---|---|
| `0x0EFC` | vblank 时钟与 strided 计数器更新 |
| `0x0ECC` | 有符号饱和/回绕累加 helper |
| `0x2C64` / `0x2CAC` | `memmove` / `memset` |
| `0x372C` | channel 地址计算 |
| `0x3842` | selector `00/10/01/20` 的表更新 |
| `0x3E4E` | packed status 检查 |
| `0x4596` | workspace byte 镜像写入 |
| `0x4680` | cart layout nibble 查询 |

静态闭包中其余入口没有在 3600 帧自动游戏路径上要求 host HLE；HWRAM resident
代码和游戏回调继续原生执行。移植时仍应保留 unknown-entry trap，按真机轨迹增补，
不能把“本游戏路径未触达”等同于所有 ST-V 游戏都不需要。

## `0x4114` 边界的纠正

旧实现把 `0x4114` 当作 snapshot-only 函数并直接返回，这是错误的调用约定：原例程
会重置 boot 栈、更新阶段状态并非返回式跳入 `0x06010808`。

现在 attract 快照路径不再伪造该返回。恢复时只规范化已经完成 bootstrap 的当前
channel 状态位，防止首个 vblank 重复请求 boot；构造式 trampoline 路径保留真正的
非返回 handoff 语义。

官方 ST-V BIOS oracle 同时确认：frame-120 的寄存器捕获点仍在 BIOS↔游戏 init
callback ping-pong 内，`PR=0x00003268` 是低 BIOS 返回链，不能直接当真机根入口。
因此 SAROO trampoline 必须主动完成 boot 构造，不能照抄这个中途寄存器快照。

## SAROO 开工输入

1. ROM 映射：沿用 `CART_STV` 已验证的 Baku Baku IC 拼装规则，先实现 CS0。
2. Trampoline：构造 HWRAM resident/向量/工作区，搬运游戏 image，初始化
   VDP/SCU/SCSP，最后进入游戏 init；不要灌 attract 快照。
3. Runtime HLE：把上表 C 语义改写成 SH-2 native routines，放在 SAROO 可执行
   的 CS0 保留区；改写 HWRAM dispatcher slots/veneer，禁止跳进 Saturn mask BIOS。
4. 输入：先提供 idle IOGA 值；运行期稳定后再接 STM32 手柄→JAMMA 翻译。
5. 断言：保留 low-PC trap、unknown-HLE trap、vblank heartbeat，并以 title、投币、
   进入游戏、持续 3600 帧作为四级验收点。

当前 `stv-trampoline` 的 Phase-1 SH-2 基线已用 `make test-build` 重新验证：生成
344-byte `trampoline.bin`，Saturn header 为 `SEGA SEGASATURN `，入口反汇编为
SH-2 big-endian `0x02000100`。Phase-2 可直接从这个可构建骨架扩展。

## 孪生回归命令

```bash
DISPLAY=:0 \
STV_AUTOPLAY=1 STV_CLEAN_HLE=1 STV_NOLOW=1 STV_INVALID=1 \
STV_BIOSCALL=1 STV_HLE_TRACE=1 STV_SHOT=1800,2400,3600 \
./build/src/gtk/yabause -b bios/saturn-jp-v100.bin --stvboot
```

证据见 [clean HLE 首帧与长跑记录](2026-07-12-clean-hle-first-frame.md) 和
`docs/img/stv-clean-hle-game-frame{1200,1800,2400,3600}.png`。

## 移植阶段退出条件

- Saturn mask BIOS 下启动，不加载 ST-V BIOS ROM；
- master SH-2 从不执行 `<0x00080000` 的 ST-V 服务地址；
- 不依赖 MAME/Yabause attract RAM 快照；
- Baku Baku 能从 trampoline 初始化进入 title，再投币进入实际游戏；
- 连续运行 3600 帧无 illegal opcode / unknown service。
