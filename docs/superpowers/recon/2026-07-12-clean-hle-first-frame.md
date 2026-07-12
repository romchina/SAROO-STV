# Clean HLE 首帧里程碑

**日期：** 2026-07-12

## 结果

Yabause twin 已在 stock Saturn BIOS 下，用 `--stvboot` 快照入口和
`STV_CLEAN_HLE=1` 跑到 frame 300，并渲染完整的 BAKU BAKU ANIMAL 标题画面。
运行中 vblank-IN / vblank-OUT 连续触发，`STV_NOLOW=1` 没有记录主 SH-2 执行
ST-V BIOS 低地址字节。

![clean HLE frame 300](../../img/stv-clean-hle-frame300.png)

复现命令：

```bash
DISPLAY=:0 \
STV_AUTOPLAY=1 STV_CLEAN_HLE=1 STV_NOLOW=1 STV_SHOT=300 \
./build/src/gtk/yabause -b bios/saturn-jp-v100.bin --stvboot
```

## 本轮实现

- `StvHleInstallRedirects()` 把 HWRAM dispatcher 的 `[0x10E8]` / `[0x10E4]`
  低 ROM 表读取改到 HWRAM sentinel，令解释器能在取 Saturn BIOS 指令前接管。
- `0x0EFC` vblank 时钟更新已原子 HLE，包括对 `0x20180001/03/05/07`
  strided 计数器的溢出更新。
- `0x372C` channel address helper 已 HLE。
- `0x3842` 已覆盖本次路径实际触达的 selector `0x00` 和 `0x10`，分别更新
  `0x06000840` 和 `0x06000830` 后 tail-jump 到 `[0x06000648]`。
- `0x4114` 暂时作为 snapshot-only scaffold：快照已经完成启动，首个 vblank
  中残留的 reset/service 条件会重复请求非返回式 boot；当前将这次重复 reset
  抑制并返回。它不是最终真机 boot HLE。

## 重要纠正

`PC=0x060335E4, R11=0` 不是安全主循环边界。该地址在当时 HWRAM 中为
`0xFFFF`，随后进入 `0x0600205A` illegal-instruction trap。精确 cache 捕获也证明
对应 cache line 无效，因此“代码只在 SH-2 cache”假设被否定。

## 当前边界

这个里程碑证明的是：**attract 快照 + Saturn BIOS + 当前 clean HLE 子集**可以
持续处理中断并渲染，不再需要执行 ST-V BIOS ROM。它还没有消除 MAME 快照，
也没有完成 `0x3842` 的其他 selector、真正的 `0x4114` boot 构造以及其余服务闭包。
下一步应扩大自动游玩帧数，让运行轨迹逐个暴露剩余 selector / 服务入口。
