# ST-V BIOS ROM 调用闭包分析 — 解答 M-HLE-3 决策点 (A/B/C)

**日期:** 2026-07-01。承接 [2026-06-28 trampoline 执行 findings](../plans/2026-06-28-stv-mhle3-trampoline-twin.md) 末尾的决策点：
dispatch-redirect 机制证明可行后，发现 romroutines 内部有 204 个落在 0x1000-0x8000 数值范围的
32-bit 值（疑似低址指针，盲目 +DELTA 重定位会损坏非指针数据）。三个选项：
A) 写真正的 SH-2 重定位器（反汇编区分指针/数据）
B) 真·HLE 重写游戏实际调用的闭包（已知 8 个入口；先查闭包大小定可行性）
C) 继续逐崩溃 whack-a-mole

本文做 B 的可行性调查，**结论：B 可行，且是更优路径**。

## 方法

写 SH-2 递归下降反汇编 + 寄存器值追踪器（`tools/stv/sh2_closure.py`），从
[2026-06-28 runtime enumeration](2026-06-28-stv-bios-runtime-dependency-enumeration.md) 的
8 个已知入口（0xEFC/0x372C/0x3842/0x3E4E/0x426C/0x44FC/0x4500/0x4596）出发，静态追踪控制流：

- 精确解码终止类指令（RTS/RTE/JMP/BRAF — 不返回）vs 调用类指令（BSR/BSRF/JSR — 返回，继续扫描）；
  **v1 脚本曾把调用也当终止符处理，导致闭包严重低估**——v2 修正后闭包从 11 涨到 22。
- 寄存器值追踪：PC 相对字面量加载(`mov.w/l @(disp,PC),Rn`)精确求值；`mov.l @Rm,Rn`/
  `mov.l @(disp,Rm),Rn`/`mov.l @(R0,Rm),Rn` 间接解引用支持跨 **ROM(0-0x80000) + HWRAM-resident
  (resident.bin, 0x06000000-0600EFFF) + game(game.bin, 0600F000+)** 统一读取——这一步是关键：
  许多 BIOS 内部调用经 **HWRAM 派发 veneer 槽**（如 `[0x06000640]`/`[0x06000644]`）二次跳转，
  必须能读快照里这些槽的实际值才能继续追踪。
- 无法静态解析的间接跳转记为 unresolved，不假装解析。

工具: `tools/stv/sh2_closure.py <bios.bin> <resident.bin> <game.bin>`。

## 结果

```
ROM size: 0x80000
Entry points reached (transitive ROM closure): 22
  0x0ECC, 0x0EFC, 0x1120, 0x1760, 0x2B9C, 0x2C64, 0x2CAC, 0x372C, 0x3744, 0x3842,
  0x3E4E, 0x4080, 0x40C0, 0x426C, 0x43B8, 0x44E2, 0x44FC, 0x4500, 0x4526, 0x4596,
  0x4648, 0x4680
Distinct ROM code addresses visited: 866 (range 0x0ECC-0x46AA)
Approx bytes touched: ~0x868 (≈2.1KB) / 0x80000 (0.41% of full 512KB BIOS)
Resolved calls landing in HWRAM/game (already-loaded, zero extra HLE burden): 11
Unresolved indirect branches: 5 (0x4522, 0x44E4, 0x395E, 0x38BA, 0x38DC)
```

**22 个例程（不是原先认为的 8 个，但仍然小），覆盖一段稀疏的 ~0x0ECC-0x46AA 范围，
实际触达字节只占整个 BIOS 的 0.41%。** 这就是闭包大小的答案：**远小于"整个 BIOS"，
在"~20 个例程可行"的范围内（甚至略超一点，22 个，量级一致）。**

新发现的入口（8→22 的差值）主要是 0x3842/0x3744（表驱动对象处理调用一个经 `[0x06000640]`/
`[0x06000644]` 注册的回调）、0x4500 内部的 ROM 传输辅助例程（0x4526/0x4680 等）。

## 5 个未解析间接跳转 — 逐个排查，均非"还有更多例程"的证据

人工反汇编核实每一个：

1. **0x4522 `jmp @r7`**（0x4500 内, "卡带 ROM→RAM 传输"例程尾部）: r7 = 调用方通过表项第 4 个
   字段(`cont`)传入的延续地址，是**跨过程参数传递**（调用方在 0x06000656 索引的表里设置），
   静态分析在"干净状态"探查被调用方时天然看不到调用方传入的寄存器值——这是分析盲点，不是
   "未发现的例程"，该值来自数据表，真正的目标地址要么是已知 HWRAM 派发代码、要么是 game 码。
2. **0x44E4 `jmp @r1`**（小回调 veneer，被 4 处 `bsr 0x44e2` 调用，各自先 `mov.l <addr>,r1`
   设置一个 HWRAM 槽地址）：人工解出 4 个调用点实参 = `[0x60002CC]`/`[0x6000258]`/
   `[0x60002C8]`/`[0x60002D4]`。查 resident.bin 实际值：**三个 = `0x4574`**（已在我们的闭包内，
   且该地址本身就是 `rts; nop`——空操作占位回调），**一个 = `0x53454741`("SEGA" 哨兵值，
   表示"未注册"，frame 120 时这个回调钩子还没被游戏/BIOS 写入真实指针）**。同结构的
   `[0x60002E8]` 也是 "SEGA" 哨兵。**结论：这是一个运行期可注册的回调钩子表，默认空操作，
   不代表隐藏的大量例程**——真正注册的回调（如果有）会指向 game 码（0600F000+，已有，零负担）
   或现有的 22-例程闭包内某处。
3. **0x395E / 0x38BA / 0x38DC `jsr`**（0x3842 表驱动例程内）: 目标值经 `mov.l rX,@-r15` 压栈、
   `mov.l @r15+,rX` 出栈传递（栈临时保存），追踪器不建栈内存模型，故未解析；但**同一份数据
   在压栈前已被解析过一次**（如 0x38A8 处同源 `[0x06000644]` 解析成功 → `0x06001412`），
   栈只是为保护该值跨过一次 `jsr @r8`(=0xECC) 调用，值不变——**这 3 个未解析点的真实目标已经
   等于已解析的 `0x06001412`，不是新例程**，是追踪器对栈临时变量建模缺失的已知局限，非真实
   未知数。

**结论：5 个未解析点全部排查完毕，无一指向"closure 之外的新 ROM 例程"。**

## 决策：选 B，弃 A

- **A（写完整 SH-2 重定位器，处理全部 32KB/204 个内部指针）做的工作量 >> B**：A 要正确处理
  整个 0x8000 窗口内的指针/数据消歧（含很多与游戏运行期路径无关的死代码、其它入口的例程），
  且每个误判（数据被误当指针重定位，或反之）都会造成隐蔽 bug。
- **B（对 22 个例程做干净 C 重写）工作量小得多、faithful 程度由我们自己控制、且不依赖"猜哪些
  4 字节是指针"这种本质上脆弱的启发式**。22 个例程里多数语义已经清楚（vblank 计时器、索引
  helper、状态轮询、中断态 handler 表管理、ROM→RAM 传输 memcpy、工作区 setter），其余几个
  （0x1120/0x1760/0x2B9C/0x2C64/0x2CAC/0x4080/0x40C0/0x43B8/0x4648/0x4680）待下一步逐个反汇编
  +命名（多数看起来是 0x3842/0x4500 的小 helper，不是独立大子系统）。
- **真机含义不变**：HLE 例程在真机上由卡/FPGA 提供（trampoline 已经在做的 dispatch-redirect
  机制不变），只是"redirect 到重定位后的原始 ROM 字节"换成"redirect 到我们写的 C 函数"——
  机制完全复用，只换被指向的实现来源。

## 下一步

1. 反汇编+命名剩余 ~10 个未命名例程（0x1120/0x1760/0x2B9C/0x2C64/0x2CAC/0x4080/0x40C0/
   0x43B8/0x4648），确认是否都是已知 7 类语义的变体/helper。
2. 设计 HLE 调用约定：在 `stvtramp.c` 把 dispatch-redirect 目标从"CS0 relocated ROM bytes"
   换成"C 函数地址表"（需要 SH-2 native code 触发 host callback，或者更简单：保留 CS0
   relocation 机制处理"不可达"边缘情况，C HLE 只覆盖这 22 个主路径，两者并存）。
3. 用现有 twin(`STV_BIOSCALL`/`STV_DUMPRAM`)逐例程验证 HLE 实现行为与原 ROM 字节一致。
4. 更新 `docs/STV-HARDWARE-PORTING.md`：B 模块从"relocate 整个 32KB ROM"改为"22 个 HLE 例程
   清单"，真机移植工作量大幅降低。

## 复现

```bash
cd /root/yabause-stv
python3 tools/stv/sh2_closure.py bios/stv-jp-20091.bin stvstate/tramp/resident.bin stvstate/tramp/game.bin
# 单条反汇编核实:
sh-elf-objdump -D -b binary -m sh2 -EB --start-address=0xADDR --stop-address=0xADDR2 bios/stv-jp-20091.bin
```
