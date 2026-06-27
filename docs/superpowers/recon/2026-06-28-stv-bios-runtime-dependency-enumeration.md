# ST-V BIOS 运行期依赖枚举 (M-HLE-3 第一步)

**日期:** 2026-06-28。平台: Yabause twin from-scratch boot (`STV_BOOT=1`)，跑到 bakubaku STAGE 1。
WSL HEAD `2442e9f4`。

## 目的

M-HLE-3 的目标是把 twin 上"靠 `-a` 加载整个 ST-V BIOS"的依赖，换成真机 SAROO 可移植的两件东西：
- **trampoline**(跑在 Saturn/卡上)复刻 ST-V BIOS 的**开机初始化**；
- **HLE**游戏运行期实际调用的那几个 ST-V BIOS ROM 例程(真机 mask ROM 改不了)。

本文枚举**运行期**那一层 = HLE 工作清单。

## 方法: STV_BIOSCALL 探针

`yabause/src/sh2int.c` 的 `SH2DebugInterpreterExec` 主循环加探针(env `STV_BIOSCALL`，仅主 SH-2)：
记录 PC 从游戏码区(low≥0x80000)**跨界进入 ST-V BIOS ROM**(low<0x80000，含 cache 镜像)的每个 (caller, PR, target) 配对，去重。

**关键过滤**: 原始 109 条里 **71 条是中断返回(RTE)污染**——异常/中断 handler(HWRAM 0x06001Fxx/0x0600205x)执行完 RTE 回到被中断的 BIOS 代码，被记成"进入 BIOS"。判据: 这些 PR 仍指向 BIOS 内部。**真·游戏→BIOS 调用 = PR 指回 HWRAM(≥0x06000000，即 JSR/BSR 返回地址在游戏码)。**

## 结果: 8 个真·运行期 BIOS ROM 例程 (HLE 清单)

反汇编自 `bios/stv-jp-20091.bin`(SH-2 大端) via `sh-elf-objdump -b binary -m sh2 -EB`。

| BIOS 例程 | 调用点(HWRAM) | 功能 | HLE 难度 |
|---|---|---|---|
| `0x00000EFC` | 0x06000D2E | **vblank 时间累加器**: 每 vblank 给 [0x06000758] 加 `0x55929FAD`，溢出调 HWRAM 0x0600052C/544。NTSC 实时钟分频。 | 易 |
| `0x0000372C` | 0x0601063A, 0x0602B486 | **索引/地址计算 helper**: [0x06000650].byte × 0xF00 + 0x20180100；另一入口调 [0x06000644]。 | 易 |
| `0x00003842` | 0x06024212, 0x0602421C | **表驱动对象/通道处理**: r4&15 选项，[0x06000650].byte<<6 索引 0x20183D80 基址的 16 项表；引用 HWRAM 0x06000640/700。 | 中 |
| `0x00003E4E` | 0x060134B4 | **状态字 nibble 检查**: 读 [0x06000658].word，逐 nibble 比 ≥8(外设/状态轮询门)。 | 易-中 |
| `0x0000426C` | 0x0603339A | **中断临界区 + handler 表管理**: SR=0xF0 屏蔽 IRQ → 改 [0x06000348]/[0x06000340]/**[0x06000610]**(vblank handler 指针)/[0x06000300] → SR=0 恢复。 | 中 |
| `0x000044FC` → `0x4500` | 0x0600202C | **卡带 ROM→RAM 传输**: [0x06000656].byte×16 索引表取 (src,dst,len,cont)；0x4526 检查 src≥`0x22200000`(A-Bus CS0 卡区) → mov.w @src+,@dst memcpy → jmp @cont。游戏从卡 ROM 载资源走这。 | 中 |
| `0x00004596` | 0x0601274C | **BIOS 工作区 byte setter**: 写 byte 到 [0x0600065A + r4]。后接数据表(0x20100xxx SMPC/IO 常量 + 0x06000xxx HWRAM 指针)。 | 极易 |

## 关键洞察: BIOS 是"HWRAM 常驻 + ROM 例程"两层

上述 ROM 例程大量引用 **HWRAM 常驻 BIOS 组件**(派发桩/向量/工作码: 0x06000300/340/348/610/640/644/650/700, 0x0600052C/544)和 **BIOS 工作变量**(0x06000650/656/658/65A/758)。游戏的 BIOS 服务调用多经 HWRAM 派发 veneer(0x06000C06/0x060014xx/0x06000D14)读函数指针再 JMP 进 ROM 例程。

**对真机的含义(两层移植)**:
1. **trampoline** 开机必须铺好 HWRAM 常驻部分: 向量表 + 派发桩 + 工作变量初值(0x06000000–0x06001000+ 区)。这部分可从 twin from-scratch boot 后的 HWRAM 快照提取目标值。
2. **HLE** 实现上面 7 类 ROM 侧逻辑(8 例程，有的同源)。难度集中在 0x3842(表驱动)/0x426C(中断表)/0x44FC(ROM 传输)，其余偏 trivial。

## 旁证 (经 HWRAM-veneer 派发进入的 BIOS ROM 例程)

另有 ~28 个 (caller=HWRAM, PR=BIOS, target==PR 模式) 条目，是 BIOS↔HWRAM-veneer 控制流回弹(RTS/JMP 进 BIOS)，多为上述例程的子程/返回点，非新增独立依赖。完整列表见 `/tmp/bioscall.log` + `/tmp/proc.py` 分类输出。地址簇: 0x00000Exx-0Fxx / 0x000031xx-35xx / 0x000037xx / 0x00003842 / 0x00003E4E / 0x000042xx-43xx / 0x000044FC-45xx / 0x000048xx-4Dxx。

## 复现

```bash
# 跑 from-scratch boot 到 STAGE 1，捕获 BIOSCALL 日志
cd /root/yabause-stv
DISPLAY=:0 STV_BOOT=1 STV_AUTOPLAY=1 STV_BIOSCALL=1 \
  timeout 150 ./build/src/gtk/yabause -b bios/stv-jp-20091.bin -a 2>/tmp/bioscall.log
python3 /tmp/proc.py          # 过滤 RTE 污染，按 PR-in-HWRAM 提取真调用
# 反汇编某例程
sh-elf-objdump -D -b binary -m sh2 -EB --adjust-vma=0 \
  --start-address=0xEFC --stop-address=0xF40 bios/stv-jp-20091.bin
```

## 下一步

- **boot 期枚举**(trampoline 工作底稿): 同法但反过来——表征 from-scratch boot 期 BIOS 做的效果(内存清零 0xD04 / VDP1/2/SCU/SCSP init / 游戏 CS0→HWRAM 搬运 / 声音 68k free-run / DISP on)，已散见 saroo memory，待整理成 trampoline 规格。
- **写 M-HLE-3 计划**: 里程碑顺序建议 = ① trampoline 复刻交接态(真 Saturn BIOS 启动，丢 `-a`) ② 逐个 HLE 上面 8 例程，twin 当 oracle 逐个验证。
