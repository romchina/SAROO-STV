# SAROO 上的 ST-V IOGA 路由边界

**日期：** 2026-07-13

## 结论

当前 SAROO 卡不能在 ST-V 原始地址 `0x00400000` 直接实现 315-5649。
该地址不属于 Saturn A-Bus CS0/CS1/CS2 窗口，卡槽不会为它产生 FPGA 可见的
片选。可行路径是把 IOGA 端口影子放到 SAROO 已有的 CS2 控制块，然后由 clean
resident 在 VBlank 中读取并转换成游戏已经使用的 HWRAM 输入影子。

## Baku 运行期访问闭包

在 Yabause cold trampoline 上对所有 IOGA byte access 记录 PC，1027 个 VBlank
样本只出现以下访问点：

| PC | 操作 | ST-V 地址 | 作用 |
|---:|---|---:|---|
| `0x0600209C` | read | Port A `0x20400001` | P1 |
| `0x060020AA` | read | Port B `0x20400003` | P2 |
| `0x060020B8` | read | Port C `0x20400005` | system/coin/start |
| `0x060020C6` | read | Port E `0x20400009` | P3 |
| `0x060020D4` | read | Port F `0x2040000B` | P4 |
| `0x060012B2` | read | Port D `0x20400007` | counter/lockout readback |
| `0x060012D0` | write | Port D `0x20400007` | counter/lockout update |

`0x06002098` poller 对 A/B/C/E/F 取反后写入 active-high longs：
`0x06002864/68/6C/70/74`。Baku 的 clean path 消费这些 HWRAM 值，不需要让
游戏直接访问不可达的低总线页。

## 当前实现

- MCU 寄存器 `0x36/0x38/0x3A/0x3C` 写入 packed active-low A/B、C/E、F/D、
  G/mode；idle 为 `FFFF/FFFF/FFFC/FF00`。
- Saturn 从 CS2 `0x25807020/22/24/26` 读取同一影子。
- native `stv_resident_input_poll` @ `0x04401140` 在 VBlank 中生成
  `0x06002864–0x06002874` 及派生 system byte `0x06000730`。
- FPGA testbench、MCU host tests 和 native layout verifier 均覆盖此契约。

## 尚未闭合

MCU本身看不到 Saturn 控制器总线；“STM32直接读 Saturn 手柄”不是当前 PCB
上的可行路径。真实手柄输入应由 Saturn SH-2 通过 SMPC INTBACK 读取，再合并到
resident 的 HWRAM 输入影子。CS2 IOGA shadow 仍适合 idle、自动测试和外部输入
注入。下一步应实现带超时的 native SMPC pad poll，并验证它不会阻塞 VBlank。
