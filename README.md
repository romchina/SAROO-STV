# SAROO-STV

**SAROO-STV 是 [SAROO](#saroo-is-a-hdloader-for-sega-saturn)（土星光驱模拟卡）的一个分叉。目标：在不改 Sega Saturn 主板的前提下，通过 SAROO 卡槽硬件让真 Saturn 启动并运行 Sega ST-V 街机游戏 ROM。**

ST-V（Titan 主板）与 Saturn 的核心硅片几乎完全相同：2× SH-2 @ 28.6MHz、68EC000 声音 CPU、SCU、VDP1、VDP2、SCSP、RAM 规格全同，**CPU 指令、图形命令、声音程序完全二进制兼容**。差异集中在外设——JAMMA I/O（315-5649）、BIOS、93C46 EEPROM、ROM 映射方式。因此理论上：SAROO 把 ST-V 卡带 ROM 映射进 Saturn 的 A-Bus + 仿冒 I/O 外设 + HLE ST-V BIOS，就能在 stock Saturn 上跑 ST-V 游戏。

## 方法：先软件孪生，再上真机

- **软件孪生（PC）**：用 Yabause（stock Saturn 模拟核心）当被验证对象、MAME（`stv`）当真值 oracle，在 PC 上验证「ST-V 游戏能在 Saturn 硅片上执行并渲染」这个核心假设。快速试错、不碰硬件。
- **真机（SAROO 硬件）**：把孪生上验证过的 ROM 映射 + 外设仿冒 + BIOS HLE 落到 FPGA（EP4CE6）/ STM32（H750），给真 Saturn。真机改不了 mask ROM，故 ST-V BIOS 例程必须 HLE。

完整路线图（Phase 0–5）见 [`docs/STV-ROADMAP.md`](docs/STV-ROADMAP.md)。

## 当前进度

**核心假设已视觉验证**：`bakubaku`（BAKU BAKU ANIMAL）的 ST-V 游戏码在 Yabause（stock Saturn 核心）上真实执行——attract 主循环 + vblank 中断健康运行、不崩；其 **VDP2 attract 背景渲染出来，像素级吻合 MAME** 真机。

| ![twin vs MAME](docs/img/stv-attract-twin-vs-mame.png) |
|:--:|
| 左 = MAME（ST-V 真值）  右 = Yabause Saturn 软件孪生。VDP2 背景层逐像素一致。 |

⚠️ 这是**快照回放孪生**（把 MAME 捕获的内存/寄存器状态灌进 Yabause 再续跑），**不是**插卡从头 boot，也**还不可玩**。已知待办：

- **DISP faithful 修复**：当前靠诊断 flag（`STV_FORCE_DISP`）强制 VDP2 显示位；根因是 replay 中 ST-V BIOS 例程 @0x34DE 关掉了 DISP，需 HLE（M-HLE-3）
- **VDP1 精灵叠加层**：INSERT COIN 文字 / 眼睛 / CREDIT 尚未渲染
- **从头引导 + 输入/投币**：未做
- **真机 SAROO HLE 路**：未开始

逆向 / 系统化调试的全过程记录见 [`docs/superpowers/recon/`](docs/superpowers/recon/)。

> 版权说明：ST-V BIOS 与游戏 ROM 受版权保护，**不包含**在本仓库中。软件孪生侧的 Yabause fork 源码独立维护（见 recon 文档）。

---

> 以下为上游 [tpunix/SAROO](https://github.com/tpunix/SAROO) 的原始说明。

### SAROO is a HDLoader for SEGA Saturn.

SAROO是一个土星光驱模拟器。SAROO插在卡槽上，实现原主板的CDBLOCK的功能，从SD卡装载游戏并运行。
SAROO同时还提供1MB/4MB加速卡功能。

--------
### 一些图片

<img src="doc/saroo_v12_top.jpg" width=48%/>  <img src="doc/saroo_v12_bot.jpg" width=48%/>
<img src="doc/saroo_scr1.png" width=48%/>  <img src="doc/saroo_scr2.png" width=48%/>
<img src="doc/saroo_dev1.png"/>
<img src="doc/saroo_devhw.jpg"/>


--------
### 开发历史

#### V1.0
最初的SAROO仅仅是在常见的usbdevcart上增加了一个usbhost接口。需要对游戏主程序进行破解，将对CDBLOCK的操作转化为对U盘的操作。
这种方式需要针对每一个游戏做修改，不具备通用性。性能与稳定性也有很大问题。只有很少的几个游戏通过这种方式跑起来了。
(V1.0相关的文件未包括在本项目中)


#### V1.1
新版本做了全新的设计。采用FPGA+MCU的方式。FPGA(EP4CE6)用来实现CDBLOCK的硬件接口，MCU(STM32F103)运行固件来处理各种CDBLOCK命令。
这个版本基本达到了预期的目的，也有游戏几乎能运行了。但也有一个致命的问题: 随机的数据错误。在播放片头动画时会出现各种马赛克，
并最终死掉。这个问题很难调试定位。这导致了本项目停滞了很长时间。


#### V1.2
1.2版本是1.1版本的bugfix与性能提升，使用了更高性能的MCU:STM32H750。它频率足够高(400MHz)，内部有足够大的SRAM，可以容纳完整的CDC缓存。
FPGA内部也经过重构，抛弃了qsys系统，使用自己实现的SDRAM与总线结构。这个版本不负众望，已经是接近完美的状态了。
同时，通过把FPGA与MCU固件逆移植到V1.1硬件之上，V1.1也基本达到了V1.2的性能了。


--------
### 当前状态

测试的几十个游戏可以完美运行。  
1MB/4MB加速卡功能可以正常使用。  
SD卡支持FAT32/ExFAT文件系统。  
支持cue/bin格式的镜像文件。单bin或多bin。  
部分游戏会卡在加载/片头动画界面。  
部分游戏会卡在进行游戏时。  


--------
### 硬件与固件

原理图与PCB使用AltiumDesign14制作。  
V1.1版本需要飞线才能正常工作。不应该再使用这个版本了。  
V1.2版本仍然需要额外的一个上拉电阻以使用FPGA的AS配置方式。  

FPGA使用Quartus14.0开发。  

Firm_Saturn使用SaturnOrbit自带的SH-ELF编译器编译。  
Firm_v11使用MDK4编译。  
Firm_V12使用MDK5编译。  


--------
### SD卡文件放置

<pre>
/ramimage.bin      ;Saturn的固件程序.
/SAROO/ISO/        ;存放游戏镜像. 每个目录放一个游戏. 目录名将显示在菜单中.
/SAROO/update/     ;存放用于升级的固件.
                   ;  FPGA: SSMaster.rbf
                   ;  MCU : ssmaster.bin
</pre>


--------
一些开发中的记录: [SAROO技术点滴](doc/SAROO技术点滴.txt)
