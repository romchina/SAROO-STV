# Baku Baku EEPROM / PDR 运行期边界

**日期：** 2026-07-13

## 结论

Baku Baku 的 clean trampoline 单游戏路径不需要在 SAROO 上实现 93C46 协议。
ST-V BIOS 原本在 boot 阶段通过 SMPC PDR1/PDR2 检查并初始化 EEPROM；clean
trampoline 已用构造式工作区替代这段 BIOS boot。游戏运行期没有直接 PDR/EEPROM
访问，因此为本游戏添加一个无法被卡槽截获的 `0x00100075/77` FPGA 模型没有意义。

## 运行期证据

在 Yabause cold trampoline + clean HLE 下对 PDR1/PDR2 全部 byte access 记录
master SH-2 PC，1027 帧内唯一访问为：

```text
1027 × PDR2 read @ 0x20100077, PC=0x060020E4
```

该 PC 属于旧 BIOS resident 的每帧 I/O poller，不是 Baku 游戏代码。当前 SAROO
clean resident 已用 `stv_resident_input_poll` 替代整个 `0x06002098` poller，并通过
SMPC INTBACK 获取 Saturn pad，因此也不再读取 PDR2。

## 范围决定

- Baku 候选镜像不附带 `.eeprom`，也不要求 `stvbios.nv`。
- 不在 FPGA 中宣称模拟不可达的 Saturn 内部 SMPC PDR 地址。
- 以后移植直接 bit-bang 93C46 的游戏时，需要先枚举并重定向其 PDR call sites，
  再增加 native 93C46 状态机和 SD 持久化；这属于多游戏兼容层，不是当前
  Baku 单游戏退出条件。
