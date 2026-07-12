# ST-V BIOS HLE 闭包语义清单

**日期：** 2026-07-12。承接 `2026-07-01-stv-bios-call-graph-closure.md` 的 Option B：
把 bakubaku 运行期触达的 ST-V BIOS ROM 闭包重写成干净 HLE，而不是重定位原 BIOS 字节。

## 结论

22 个闭包入口已全部归类。新增的 14 个入口没有引入未知大子系统；它们主要是 8 个外部服务入口的
内部 helper。最适合先独立实现和做差分测试的是 `0x1760`、`0x2B9C`、`0x2C64`、`0x2CAC`。

下列名称是项目内部的**描述性名称**，不是 Sega 原符号。带 `?` 的两个硬件流程仍需动态等价验证后定名。

| 地址 | 描述性名称 | 语义 / HLE 契约 |
|---:|---|---|
| `0x0ECC` | `signed_accumulate_saturate` | `r0=r4+r5`；若负的 `r4` 加法后跨到非负区间，则返回 `-1`。vblank 时间更新用它处理回绕后的偏移。 |
| `0x0EFC` | `vblank_clock_update` | 更新 `[0x06000758]` 的 NTSC 时间累加器，溢出时调用两个 HWRAM 回调。 |
| `0x1120` | `sound_driver_unpack_init` | 置声音初始化 busy 位，把压缩的 68K 驱动解到 sound RAM，建立声音工作区指针，最后清 busy 位。 |
| `0x1760` | `sega_lz_decompress` | 位流 LZ 解压；`r4=src, r5=dst`，`r0=输出字节数`。包含 literal、短回溯和长回溯三种 token。 |
| `0x2B9C` | `signed_div32_nonabi` | SH-2 展开式有符号 32 位除法。非标准 ABI：`r1=被除数, r0=除数`，商返回 `r0`；除数为零还写诊断字。 |
| `0x2C64` | `memmove` | `r4=dst, r5=src, r6=len`，处理重叠，返回原 `dst`。 |
| `0x2CAC` | `memset` | `r4=dst, r5=byte, r6=len`，返回原 `dst`。 |
| `0x372C` | `channel_address` | 根据 `[0x06000650]` 计算通道/对象地址。 |
| `0x3744` | `channel_callback` | 通过 `[0x06000644]` 调用 HWRAM 通道回调。 |
| `0x3842` | `channel_table_dispatch` | 按 `r4 & 15` 和 `[0x06000650]` 选择对象表项，驱动注册回调。 |
| `0x3E4E` | `packed_status_test` | 检查 `[0x06000658]` 中的 packed nibble 状态门。 |
| `0x4080` | `sound_init_wrapper` | 清声音状态位，构造 16 字节参数块后调用 `0x1120`。 |
| `0x40C0` | `sound_workflag_set?` | 设置 `[0x0600065B]` bit 4 并镜像到 `0x20100077`。具体寄存器名待动态确认。 |
| `0x426C` | `handler_table_update` | 在 IRQ 临界区更新中断/服务 handler 表，必要时走声音初始化和系统复位分支。 |
| `0x43B8` | `system_reset_sequence?` | 发 SMPC 命令 `0x03/0x1A`，重设 SCU/VDP/向量和系统状态；部分路径进入 sleep。 |
| `0x44E2` | `callback_veneer` | `jmp @r1` 小型 callback veneer。 |
| `0x44FC` | `cart_transfer_entry` | 卡带传输服务入口，转入 `0x4500`。 |
| `0x4500` | `cart_transfer_dispatch` | 按 `[0x06000656]` 选择 `(src,dst,len,cont)` 描述符。 |
| `0x4526` | `cart_transfer_copy` | 校验/修正卡带源地址，逐 word 复制，随后跳 `cont`。 |
| `0x4596` | `workspace_byte_set` | `[0x0600065A + r4] = r5.byte`。 |
| `0x4648` | `smpc_command_handshake` | 对 SMPC `SF` 做等待握手并向 `COMREG` 写 `r4.byte`。 |
| `0x4680` | `cart_layout_nibble` | 从 HWRAM 配置字中按布局模式取 4-bit bank/layout 值。 |

## 闭包内部调用边

增强后的 `tools/stv/sh2_closure.py` 会直接输出 27 条已解析 ROM 调用边以及目标语义名。关键分组：

- `0x1120 → {0x1760, 0x2B9C, 0x2C64, 0x2CAC}`：声音驱动解包初始化依赖的纯算法组。
- `0x3842 → {0x3744, 0x0ECC}`：通道表派发与 HWRAM 回调组。
- `0x426C → {0x44E2, 0x4080, 0x43B8, 0x40C0}`：handler 更新的硬件状态分支。
- `0x43B8 → 0x4648`：系统流程通过统一 SMPC 握手发送命令。
- `0x4500 → {0x4526, 0x4680}`：卡带资源传输组。

原报告中的 5 个 unresolved 间接跳转仍然都已解释为 continuation/HWRAM callback，不扩展 ROM 闭包。

## 实现顺序

1. 先实现纯算法组并用随机/边界向量做原 BIOS vs HLE 差分：LZ、除法、`memmove`、`memset`。
2. 实现无复杂外设副作用的叶子：`workspace_byte_set`、`packed_status_test`、`cart_layout_nibble`。
3. 实现 callback/通道组；用现有 `STV_BIOSCALL` 和 RAM dump 比对每次调用后的寄存器与工作区。
4. 实现 cart transfer 组，再处理 sound init。
5. 最后实现 handler/SMPC/reset 组；这组必须同时比较寄存器写序列和时序，而不只比较最终 RAM。

完成标准不只是“能进 attract”：`STV_NOLOW=1` 下主 SH-2 不执行 `<0x00080000`，且自动游玩到
STAGE 1，关键 RAM/VDP 状态与原 ST-V BIOS 路径一致。

## 复现

```bash
cd /root/yabause-stv
python3 tools/stv/sh2_closure.py \
  bios/stv-jp-20091.bin \
  stvstate/tramp/resident.bin \
  stvstate/tramp/game.bin
```
