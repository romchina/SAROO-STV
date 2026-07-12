# SAROO A-Bus 地址上限与 Baku Baku 重定位边界

**日期：** 2026-07-13

## 硬件结论

Saturn 卡槽提供 AA0-AA25，CS0 逻辑范围是 `0x02000000-0x03ffffff`。
SAROO v1.x 原理图中，FPGA 只连接 AA0-AA23；AA24、AA25 到达卡槽连接器，
但没有经过电平转换器进入 FPGA。因此，现有 PCB 在同一个片选内只能区分
16 MB，无法仅靠 RTL 直接实现原生 32 MB CS0。

这也确认 `SSMaster.v` 把 `SS_ADDR[23:0]` 当作字节地址是正确的；把它整体
左移会破坏现有 cache/SDRAM 的字地址与字节选择逻辑，不能补回缺失的 AA24。

## 现有 PCB 的映射方案

- CS0 `0x02000000-0x02ffffff` → image offset `0x0000000-0x0ffffff`。
- CS1 `0x04000000-0x04ffffff` → image offset `0x1000000-0x1ffffff`。
- MCU `st_reg_ctrl[11]` 明确启用只读 ST-V ROM 模式；`st_reg_ctrl[10]`
  只在大于 16 MB 的 ST-V image 上启用 CS1 SDRAM 窗口；
  普通 SAROO 路径保持原行为。
- boot overlay 把 CS0 低 4 KB 临时映射到 image offset `0x1f00000`。
  trampoline 跳至永久 CS1 alias `0x04f00000` 后，写 `0x2580701c` 关闭
  overlay，CS0 低地址随即恢复真实 FPR。

## Baku Baku 上半区访问枚举

在 Yabause clean-HLE twin 的 CS0 read handler 上临时记录
`0x03000000-0x033fffff`，连续运行 70 秒（覆盖约 3600 帧时间），唯一命中：

| 执行 PC | 返回地址 PR | 访问 | 含义 |
|---|---|---|---|
| `0x0604afde` | `0x06035314` | long `0x033f4724` | long-copy，入口 `0x0604afd4`，源指针 R5 |
| `0x06053cd2` | `0x0604553e` | byte `0x033b96cb` | memmove，入口 `0x06053c98`，源来自资源描述符 |

两个命中都是通用复制例程内部的源读取。native HLE 的硬件移植版应给这两个
入口安装 veneer：当源地址位于 `0x03000000-0x033fffff` 时加
`0x01000000`，再执行原复制语义。这样只重定位真实访问，不对 FPR/MPR 数据中
大量偶然形似 `0x03xxxxxx` 的字节做危险的全局替换。

临时 Yabause 埋点在枚举后已撤销。

## Native veneer 验证

`stv-native-hle` 已把两个例程实现为 CS1 原生 SH-2 代码：

- `0x04400000`：long-copy source relocation；
- `0x04400034`：overlap-safe memmove source relocation；
- `0x04400088`：向 `0x0604AFD4` / `0x06053C98` 写绝对 jump stub 的安装器。

Yabause twin 临时改为与现有 PCB 相同的 CS0 16 MB 回绕和 CS1 高窗口，加载该
192-byte binary 并实际由 SH-2 执行。70 秒自动游玩期间没有 invalid opcode、
LOWPC/LOWEDGE 或 unknown HLE；CS1 trace 确认原 `0x033B96CB` 数据读取变为
image offset `0x13B96CB`。临时 twin 修改在验证后已全部撤销。

## Native leaf service 进度

在保持前三个入口地址不变的前提下，native image 扩展到 832 bytes，并增加：

| 原 BIOS | Native | 动态测试 |
|---:|---:|---|
| `0x0ECC` | `0x04400100` | 正常相加、负→非负饱和 |
| `0x3E4E` | `0x04400120` | 全 busy、任一 ready nibble |
| `0x4596` | `0x04400160` | HWRAM 与 `0x201000xx` 双写 |
| `0x4680` | `0x044001A0` | channel 2 nibble 选择 |
| `0x372C` | `0x044001E0` | channel 地址与符号扩展 |
| `0x2CAC` | `0x04400220` | 返回值及 5-byte memset |

连同已有 `0x2C64` memmove，已实现服务对在 `0x04400300` 输出固定的
original→native redirect table。Yabause SH-2 interpreter 直接执行上述入口，
11 项寄存器/内存断言全部通过；自测 harness 随后撤销。运行期 clean-HLE 还剩
`0x0EFC` vblank update 和 `0x3842` channel-table dispatch 两个复杂入口。

当前第四迭代已提供 `0x04400260` vblank steady-state 和
`0x04400400` channel dispatch（selector 0/10/1/20）；selector 0 已在 SH-2
twin 中动态验证，overflow 与 selector 1/20 边界向量仍待补齐。
