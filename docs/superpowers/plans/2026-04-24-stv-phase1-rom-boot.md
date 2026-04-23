# Phase 1 — ROM Mapping + Saturn IPL Boot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 SAROO 硬件把 SD 卡上的 ROM 镜像映射到 Saturn A-Bus CS0，Saturn IPL 启动时识别并跳入，在 VDP2 上打印 "SAROO-STV Phase 1 OK" + ROM 头 hex dump。**不要求 ST-V 游戏真跑起来**——只要求 SH-2 能读到 ROM 内容并执行一段可见代码。

**Architecture:** 复用 SAROO 已有的 "SDRAM 映射到 CS0" 能力（原本给 1/4MB RAM Cart 用），新增"ROM 模式"配置位（只读、不同地址映射）。STM32 固件增加 `stv_rom.c` 模块，负责从 SD 读 ROM 文件、写入 SDRAM、配置 FPGA 进入 ROM 模式。Saturn 侧写一个 stub trampoline 放在 ROM 起始，带 Saturn 格式启动头，让 Saturn IPL 认出。

**Tech Stack:**
- FPGA: Verilog + Quartus 14.0/18.1 Lite (Cyclone IV EP4CE6)
- FPGA sim: iverilog + GTKWave
- MCU: STM32H750 + MDK5 / arm-none-eabi-gcc, FatFS, FSMC
- Saturn side: SH-2 asm + C, Yaul SDK 或 SaturnOrbit
- Integration test: Mednafen ≥ 1.30

---

## File Structure

**Create:**
- `FPGA/sim/tb_cs0_rom.v` — testbench for CS0 ROM mode
- `FPGA/sim/run_sim.sh` — wrapper for iverilog+gtkwave
- `FPGA/sim/README.md` — how to run sims
- `Firm_MCU/Saturn/stv_rom.c` — ST-V ROM loader (SD → SDRAM)
- `Firm_MCU/Saturn/stv_rom.h` — loader public API
- `Firm_MCU/tests/test_stv_rom.c` — host-compiled unit tests
- `Firm_MCU/tests/Makefile` — host test build
- `stv-trampoline/main.c` — Saturn-side trampoline (prints hello, halts)
- `stv-trampoline/header.s` — Saturn cart boot header with `SEGA SEGASATURN` magic
- `stv-trampoline/ldscript` — SH-2 linker script (entry at cart base)
- `stv-trampoline/Makefile` — SH-ELF build
- `docs/phase1-fpga-regs.md` — FPGA register map additions

**Modify:**
- `FPGA/SSMaster.v` — add ROM mode to `ss_cs0_type`, add register bit for ROM base offset
- `Firm_MCU/Saturn/saturn_main.c` — add `stv_rom_load()` call path
- `Firm_MCU/Main/shell.c` — add `stvload <path>` debug command
- `Firm_Saturn/main.c` — add "Load ST-V ROM" menu entry

---

## Prerequisites (one-time environment setup)

- [ ] **Step 1: Verify Quartus builds original SSMaster.v unchanged**

```bash
cd FPGA
quartus_sh --flow compile SSMaster
```

Expected: `output_files/SSMaster.rbf` generated, 0 errors, resource utilization under 100%.

- [ ] **Step 2: Verify iverilog installed and runs a trivial testbench**

```bash
cat > /tmp/smoke.v << 'EOF'
module smoke; initial begin $display("OK"); $finish; end endmodule
EOF
iverilog -o /tmp/smoke.vvp /tmp/smoke.v && vvp /tmp/smoke.vvp
```

Expected: `OK`.

- [ ] **Step 3: Verify Mednafen can boot a known-good Saturn CD image**

Confirm `mednafen some_saturn_game.cue` shows game running. This will be the predictive testbed before real hardware.

- [ ] **Step 4: Verify SH-ELF toolchain**

```bash
sh-elf-gcc --version
```

Expected: version info printed, no "command not found".

- [ ] **Step 5: Commit toolchain notes**

```bash
cat > docs/phase1-toolchain.md << 'EOF'
# Phase 1 verified toolchain

- Quartus: <version output from Step 1>
- iverilog: <version>
- Mednafen: <version>
- SH-ELF GCC: <version>
EOF
git add docs/phase1-toolchain.md
git commit -m "docs: record Phase 1 verified toolchain"
```

---

## Task 1: FPGA testbench skeleton for existing CS0 path

**Files:**
- Create: `FPGA/sim/tb_cs0_rom.v`
- Create: `FPGA/sim/run_sim.sh`
- Create: `FPGA/sim/README.md`

Goal: establish simulation infrastructure that runs unchanged `SSMaster.v` with a simulated Saturn-side A-Bus master and a simulated SDRAM model. This is the baseline before any code change.

- [ ] **Step 1: Write the testbench that drives a CS0 read at addr 0x02000000 and expects a deterministic response**

```verilog
// FPGA/sim/tb_cs0_rom.v
`timescale 1ns/1ps

module tb_cs0_rom;

    // --- clocks/reset ---
    reg CLK_50M = 0;
    reg SS_MCLK = 0;
    reg SS_RST  = 0;
    always #10 CLK_50M = ~CLK_50M;   // 50 MHz
    always #17 SS_MCLK = ~SS_MCLK;   // ~28.6 MHz

    // --- Saturn A-Bus stimulus ---
    reg[23:0] SS_ADDR = 0;
    wire[15:0] SS_DATA;
    reg[15:0] ss_data_drv = 16'hzzzz;
    assign SS_DATA = ss_data_drv;
    reg SS_CS0 = 1, SS_CS1 = 1, SS_CS2 = 1;
    reg SS_RD = 1, SS_WR0 = 1, SS_WR1 = 1;
    wire SS_WAIT;

    // --- SDRAM model stubs (tied off for now; real model added Task 2) ---
    wire SD_CKE, SD_CLK, SD_CS_n, SD_WE_n, SD_CAS_n, SD_RAS_n;
    wire[12:0] SD_ADDR; wire[1:0] SD_BA; wire[1:0] SD_DQM;
    wire[15:0] SD_DQ;

    // --- STM32 FSMC stubs ---
    reg ST_CLK = 0, ST_CS = 1, ST_RD = 1, ST_WR = 1;
    reg ST_ALE = 0, ST_BL0 = 1, ST_BL1 = 1;
    reg[7:0] ST_ADDR = 0;
    wire[15:0] ST_AD;
    reg[15:0] st_ad_drv = 16'hzzzz;
    assign ST_AD = st_ad_drv;
    wire ST_WAIT;
    reg ST_GPIO0 = 0;  // NRESET

    // SAROO DUT
    SSMaster dut(
        .CLK_50M(CLK_50M),
        .SD_CKE(SD_CKE), .SD_CLK(SD_CLK), .SD_CS(SD_CS_n),
        .SD_WE(SD_WE_n), .SD_CAS(SD_CAS_n), .SD_RAS(SD_RAS_n),
        .SD_ADDR(SD_ADDR), .SD_BA(SD_BA), .SD_DQM(SD_DQM), .SD_DQ(SD_DQ),
        .PSRAM_CS(),
        .SS_MCLK(SS_MCLK), .SS_RST(SS_RST),
        .SS_SCLK(1'b0), .SS_SSEL(), .SS_BCK(), .SS_LRCK(), .SS_SD(),
        .SS_FC0(1'b0), .SS_FC1(1'b0), .SS_TIM0(1'b0), .SS_TIM1(1'b0),
        .SS_TIM2(1'b0), .SS_AAS(1'b0),
        .SS_ADDR(SS_ADDR), .SS_DATA(SS_DATA),
        .SS_CS0(SS_CS0), .SS_CS1(SS_CS1), .SS_CS2(SS_CS2),
        .SS_RD(SS_RD), .SS_WR0(SS_WR0), .SS_WR1(SS_WR1),
        .SS_WAIT(SS_WAIT), .SS_IRQ(),
        .SS_DATA_OE(), .SS_DATA_DIR(), .SS_OUTEN(),
        .ST_CLK(ST_CLK), .ST_AD(ST_AD), .ST_ADDR(ST_ADDR),
        .ST_CS(ST_CS), .ST_RD(ST_RD), .ST_WR(ST_WR),
        .ST_BL0(ST_BL0), .ST_BL1(ST_BL1), .ST_ALE(ST_ALE),
        .ST_WAIT(ST_WAIT),
        .ST_GPIO0(ST_GPIO0), .ST_GPIO2(), .ST_GPIO3(1'b0),
        .ST_MCLK(1'b0), .ST_BCK(1'b0), .ST_LRCK(1'b0), .ST_SDO(1'b0),
        .LED0(), .LED1(),
        .EPCS_CS(), .EPCS_CLK(), .EPCS_DI(), .EPCS_DO(1'b0)
    );

    // test sequence
    initial begin
        $dumpfile("tb_cs0_rom.vcd");
        $dumpvars(0, tb_cs0_rom);

        // release reset
        #1000 ST_GPIO0 = 1;

        // CS0 read at 0x02000000 (=> SS_ADDR 0x000000, SS_CS0 low)
        #500
        SS_ADDR = 24'h000000;
        SS_CS0 = 0;
        SS_RD = 0;
        #500
        SS_CS0 = 1;
        SS_RD = 1;

        #2000 $finish;
    end

endmodule
```

- [ ] **Step 2: Write the runner script**

```bash
# FPGA/sim/run_sim.sh
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

SRC="../SSMaster.v ../cachebus.v ../cdcfifo.v ../memhub.v ../tsdram.v"

# stubs for Quartus megawizard modules not needed in sim
# (mainpll and cdcfifo are .qip — replace with hand stubs for iverilog)

iverilog -g2012 -o tb_cs0_rom.vvp \
    -DSIM \
    tb_cs0_rom.v \
    stubs/mainpll_stub.v \
    stubs/cdcfifo_stub.v \
    $SRC

vvp tb_cs0_rom.vvp
echo "VCD: $(pwd)/tb_cs0_rom.vcd"
```

- [ ] **Step 3: Create Altera megafunction stubs for iverilog**

```verilog
// FPGA/sim/stubs/mainpll_stub.v
module mainpll(input wire inclk0, output wire c0, output wire c1, output wire locked);
    assign c0 = inclk0;       // mclk stub
    assign c1 = inclk0;       // sdclk stub
    assign locked = 1'b1;
endmodule
```

```verilog
// FPGA/sim/stubs/cdcfifo_stub.v
module cdcfifo(
    input sclr, input clock,
    input rdreq, output[15:0] q,
    input wrreq, input[15:0] data,
    output empty, output[10:0] usedw, output full);
    // Simple 1-entry stub - enough for compilation, not functional FIFO
    reg[15:0] mem;
    reg is_empty = 1'b1;
    always @(posedge clock) begin
        if(sclr) is_empty <= 1'b1;
        else if(wrreq) begin mem <= data; is_empty <= 1'b0; end
        else if(rdreq) is_empty <= 1'b1;
    end
    assign q = mem;
    assign empty = is_empty;
    assign full = 1'b0;
    assign usedw = 11'b0;
endmodule
```

- [ ] **Step 4: Run the testbench and confirm it compiles and exits cleanly**

```bash
chmod +x FPGA/sim/run_sim.sh
bash FPGA/sim/run_sim.sh
```

Expected: no compile errors, `VCD: .../tb_cs0_rom.vcd` printed, simulation finishes.

- [ ] **Step 5: Write the README**

```markdown
# FPGA Simulation

## Running

```bash
bash run_sim.sh
gtkwave tb_cs0_rom.vcd
```

## Adding a new testbench

1. Create `tb_<name>.v` copying `tb_cs0_rom.v` as a starting point.
2. Add a runner target in `run_sim.sh`.
3. PLL and CDC FIFO stubs live in `stubs/`; add more stubs there as needed.
```

- [ ] **Step 6: Commit**

```bash
git add FPGA/sim/
git commit -m "feat(fpga): sim infrastructure for CS0 path"
```

---

## Task 2: Add SDRAM behavioral model to simulation

**Files:**
- Create: `FPGA/sim/stubs/sdram_model.v`
- Modify: `FPGA/sim/run_sim.sh` (add sdram model)
- Modify: `FPGA/sim/tb_cs0_rom.v` (wire sdram model, preload pattern)

Goal: a behavioral SDRAM model so the testbench can actually observe read data, and a backdoor `$readmemh` loader so the TB can pre-populate ROM content without simulating the full STM32 FSMC path.

- [ ] **Step 1: Write a minimal SDRAM behavioral model with backdoor load**

```verilog
// FPGA/sim/stubs/sdram_model.v
// Minimal SDR SDRAM model: 64Mbit (4M x 16), 4 banks.
// Supports ACTIVATE, READ, WRITE, PRECHARGE, REFRESH, NOP.
// NOT a full spec model — enough to observe CAS-latency-2 reads.
module sdram_model(
    input CKE, input CLK, input CS_n, input RAS_n, input CAS_n, input WE_n,
    input[12:0] A, input[1:0] BA, input[1:0] DQM, inout[15:0] DQ);

    reg[15:0] mem[0:4*1024*1024-1];  // 4M x 16 per bank (shared for simplicity)

    // Backdoor load
    task load_hex(input[1023:0] path);
        begin $readmemh(path, mem); end
    endtask

    // ... [CMD decoding omitted for brevity; real file ~150 lines]
    // See Micron MT48LC4M16 model as reference for full behavior.

endmodule
```

**Note:** a full SDR SDRAM model is ~150–300 lines. Either:
- (a) write it ground-up (~1 day of focused work)
- (b) use Micron's reference MT48LC4M16 model (freely downloadable, BSD-ish license), check it into `FPGA/sim/stubs/` with attribution
- (c) bypass SDRAM entirely with a simpler "register-file" SDRAM stub that just responds to READs with whatever the backdoor loaded

**Pick option (c) for Phase 1** — simplest. Full SDRAM timing verification is deferred to hardware bring-up.

```verilog
// FPGA/sim/stubs/sdram_model.v (option c — simplified)
module sdram_model(
    input CKE, input CLK, input CS_n, input RAS_n, input CAS_n, input WE_n,
    input[12:0] A, input[1:0] BA, input[1:0] DQM, inout[15:0] DQ);

    parameter MEM_SIZE = 4*1024*1024;  // 8 MB
    reg[15:0] mem[0:MEM_SIZE-1];

    reg[23:0] row_addr[0:3];
    reg[15:0] dq_out = 16'hzzzz;
    reg dq_drive = 1'b0;

    assign DQ = dq_drive ? dq_out : 16'hzzzz;

    // Decode: CS_n=0 && !RAS_n => ACTIVATE; CS_n=0 && !CAS_n && WE_n => READ
    always @(posedge CLK) begin
        if(CKE && !CS_n) begin
            if(!RAS_n && CAS_n && WE_n) begin
                // ACTIVATE bank BA row A
                row_addr[BA] <= {A, 9'b0};
            end else if(RAS_n && !CAS_n && WE_n) begin
                // READ bank BA col A (9-bit col)
                dq_out <= mem[(row_addr[BA] | A[8:0])];
                dq_drive <= 1'b1;
            end else begin
                dq_drive <= 1'b0;
            end
        end
    end

    task load_hex(input[1023:0] path);
        begin $readmemh(path, mem); end
    endtask

endmodule
```

- [ ] **Step 2: Wire the SDRAM model into the testbench**

In `tb_cs0_rom.v`, replace the SDRAM stub tie-offs with:

```verilog
    sdram_model sdram(
        .CKE(SD_CKE), .CLK(SD_CLK), .CS_n(SD_CS_n),
        .RAS_n(SD_RAS_n), .CAS_n(SD_CAS_n), .WE_n(SD_WE_n),
        .A(SD_ADDR), .BA(SD_BA), .DQM(SD_DQM), .DQ(SD_DQ));

    initial begin
        // ROM content: 0x02000000 = "SEGA SEGASATURN " (first 16 bytes)
        sdram.mem[0] = 16'h5345;  // "SE"
        sdram.mem[1] = 16'h4741;  // "GA"
        sdram.mem[2] = 16'h2053;  // " S"
        sdram.mem[3] = 16'h4547;  // "EG"
        // ... rest filled with 0xDEAD pattern
    end
```

- [ ] **Step 3: Extend the test sequence to assert read data**

```verilog
    reg[15:0] captured;
    initial begin
        // ... existing reset/setup ...

        // First set ss_cs0_type = 2'b00 (Bootrom mode — needs FPGA ctrl write first)
        // ... [see Task 4 for FSMC sequence] ...

        // Then drive CS0 read at 0x02000000
        wait(SS_RST == 1 && /* mclk stable */);
        #1000
        SS_ADDR = 24'h000000;
        SS_CS0 = 0;
        SS_RD = 0;
        wait(SS_WAIT == 0);
        captured = SS_DATA;
        SS_CS0 = 1;
        SS_RD = 1;

        if(captured != 16'h5345) begin
            $display("FAIL: expected 0x5345 at 0x02000000, got 0x%04x", captured);
            $finish(1);
        end
        $display("PASS: CS0 read returned 0x%04x", captured);

        #2000 $finish;
    end
```

- [ ] **Step 4: Run and verify the baseline test FAILS (because ss_cs0_type defaults to Bootrom mode=00 but SDRAM hasn't been loaded in a way current logic expects — we expect a meaningful failure not a compilation error)**

```bash
bash FPGA/sim/run_sim.sh
```

Expected: either PASS (if default already maps SDRAM to CS0) or a specific mismatch. Document the actual observed value — this is the baseline.

- [ ] **Step 5: Commit**

```bash
git add FPGA/sim/stubs/sdram_model.v FPGA/sim/tb_cs0_rom.v FPGA/sim/run_sim.sh
git commit -m "feat(fpga-sim): simplified SDRAM model with backdoor load"
```

---

## Task 3: FPGA — add explicit "ROM mode" for CS0

**Files:**
- Modify: `FPGA/SSMaster.v:484` (extend `ss_cs0_type` meaning)
- Modify: `FPGA/sim/tb_cs0_rom.v` (test ROM mode explicitly)

Goal: dedicated ROM mode that (a) is read-only (writes from Saturn are ignored), (b) reserves type code `2'b00` cleanly for Bootrom-style behavior, (c) exposes a bit saying "we are in ST-V mode" for future phases to key off.

Currently `ss_cs0_type` has 4 values. Type `00` is labeled "Bootrom" and is the default (see line 515: `ss_reg_ctrl <= 16'h0100` which sets bit 8 but types 13:12 = 00). This already maps SDRAM to CS0. We just need to enforce read-only in this mode.

- [ ] **Step 1: Write the test: a CS0 WRITE in ROM mode must not change SDRAM content**

Add to `tb_cs0_rom.v`:

```verilog
    // After the successful read test...
    // Attempt Saturn-side write to 0x02000000
    SS_ADDR = 24'h000000;
    SS_CS0 = 0;
    SS_WR0 = 0;
    SS_WR1 = 0;
    ss_data_drv = 16'hBEEF;
    #100
    SS_CS0 = 1; SS_WR0 = 1; SS_WR1 = 1;
    ss_data_drv = 16'hzzzz;
    #200

    // Re-read
    SS_ADDR = 24'h000000;
    SS_CS0 = 0;
    SS_RD = 0;
    wait(SS_WAIT == 0);
    captured = SS_DATA;
    SS_CS0 = 1; SS_RD = 1;

    if(captured == 16'hBEEF) begin
        $display("FAIL: write in ROM mode succeeded (should be read-only)");
        $finish(1);
    end
    $display("PASS: ROM mode is read-only");
```

- [ ] **Step 2: Run, expect FAIL**

```bash
bash FPGA/sim/run_sim.sh
```

Expected: FAIL — current FPGA gateware allows writes in all modes.

- [ ] **Step 3: Gate writes in Bootrom mode**

In `FPGA/SSMaster.v`, find the write path to SDRAM (via `memhub`) and add a mode gate. The CS0 write path feeds through `ss_ram_cs = ~SS_CS0` and `ss_mask = {SS_WR0, SS_WR1}`. Gate:

```verilog
    // line ~665 (replace):
    wire ss_rom_mode = (ss_cs0_type == 2'b00);
    wire ss_ram_cs = ~SS_CS0 & ~(ss_rom_mode & (SS_WR0==0 | SS_WR1==0));
```

Actually cleaner: pass a write-enable through to memhub. Add to SSMaster.v (around the memhub instantiation):

```verilog
    wire ss_write_blocked = (ss_cs0_type == 2'b00);  // ROM mode blocks writes
    wire[1:0] ss_mask_gated = ss_write_blocked ? 2'b11 : ss_mask;

    memhub _mh(
        NRESET, mclk,
        ss_ram_cs, ss_rd_start, ss_wr_start, ss_mask_gated, ss_ram_wait, ss_ram_addr, ss_ram_din, ss_ram_dout,
        /* rest unchanged */
    );
```

(Verify `memhub.v` uses mask `2'b11` to mean "no write" — common SDRAM semantics. If different, adjust.)

- [ ] **Step 4: Re-run, expect PASS**

```bash
bash FPGA/sim/run_sim.sh
```

Expected: PASS.

- [ ] **Step 5: Add a test: ROM mode is selectable via STM32 control register write**

```verilog
    // Before the read tests — write ss_reg_ctrl[13:12] = 2'b01 (Data Cart)
    // via FSMC, then verify write is allowed; then back to 2'b00 and verify blocked.
    // [Full FSMC driver task sequence — 20 lines of ALE/AD/CS toggling]
```

- [ ] **Step 6: Run and commit**

```bash
bash FPGA/sim/run_sim.sh
git add FPGA/SSMaster.v FPGA/sim/tb_cs0_rom.v
git commit -m "feat(fpga): enforce read-only for CS0 ROM mode"
```

---

## Task 4: FPGA — add ROM base offset register

**Files:**
- Modify: `FPGA/SSMaster.v` (add register at FSMC 8'h30, wire into `ss_ram_addr` mapping)
- Modify: `FPGA/sim/tb_cs0_rom.v`
- Create: `docs/phase1-fpga-regs.md`

Goal: STM32 configurable SDRAM base offset for the ROM image. Current code at SSMaster.v:678 hardwires `ss_ram_addr[23:21] <= SS_ADDR[23:21]`. For ST-V we may want ROM placed at a non-zero SDRAM offset so the CD Block image (for fallback Saturn-CD mode) can coexist.

- [ ] **Step 1: Test — after STM32 writes `ss_rom_base = 0x100000`, CS0 read at 0x02000000 should return SDRAM[0x100000]**

```verilog
    // tb_cs0_rom.v - new test section
    sdram.mem[24'h100000 >> 1] = 16'hFEED;
    // ... FSMC write: reg 8'h30 = 16'h0010 (bits [15:11]=0 offset / bits [10:0]=word offset >> 12)
    // [Detailed FSMC driver 15 lines]
    // Then CS0 read at 0x02000000 should yield 0xFEED
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Add register in SSMaster.v**

```verilog
    // New register — ROM base offset in 1MB granularity (bits [15:0] = MB offset)
    reg[15:0] ss_rom_base;

    always @(negedge NRESET or posedge mclk) begin
        if(NRESET==0)
            ss_rom_base <= 16'h0000;
        else if(st_wr_start==1 && fsmc_addr[24]==0 && fsmc_addr[7:0]==8'h30)
            ss_rom_base <= ST_AD;
    end

    // Add to FSMC read mux (line ~394):
    // (fsmc_addr[7:0]==8'h30)? ss_rom_base :

    // Modify ss_ram_addr calc (around line 674):
    reg[25:0] ss_ram_addr;
    always @(posedge mclk) begin
        if(ss_cs0_type == 2'b00) begin
            // ROM mode — apply ss_rom_base
            ss_ram_addr <= {ss_rom_base[9:0], SS_ADDR[15:0]} + {SS_ADDR[23:16], 16'b0};
        end else begin
            // legacy RAM cart mapping (unchanged)
            ss_ram_addr[25:24] <= 2'b0;
            ss_ram_addr[23:21] <= SS_ADDR[23:21];
            if(SS_ADDR[23:22]==2'b01 && ss_cs0_type==2'b10)
                ss_ram_addr[20:19] <= 2'b00;
            else
                ss_ram_addr[20:19] <= SS_ADDR[20:19];
            ss_ram_addr[18:0] <= SS_ADDR[18:0];
        end
    end
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Document the register map**

```markdown
# docs/phase1-fpga-regs.md

## New FPGA registers (accessed via STM32 FSMC at fsmc_addr[7:0])

| Addr | Name | R/W | Purpose |
|------|------|-----|---------|
| 0x30 | ss_rom_base | R/W | ROM base in SDRAM, 1MB granularity. Active only when ss_cs0_type == 2'b00 |

## ss_reg_ctrl meaning (existing + Phase 1 additions)

| Bits | Name | Purpose |
|------|------|---------|
| [13:12] | ss_cs0_type | 00=Bootrom/ROM, 01=DataCart, 10=1MB RAM, 11=4MB RAM |
| [15] | ss_cdc_en | CD Block read enable |
| [8] | (existing debug LED driver) | — |
```

- [ ] **Step 6: Commit**

```bash
git add FPGA/SSMaster.v FPGA/sim/tb_cs0_rom.v docs/phase1-fpga-regs.md
git commit -m "feat(fpga): add ss_rom_base register for ROM-mode address offset"
```

---

## Task 5: Saturn trampoline — minimal "hello" ROM

**Files:**
- Create: `stv-trampoline/header.s`
- Create: `stv-trampoline/main.c`
- Create: `stv-trampoline/ldscript`
- Create: `stv-trampoline/Makefile`
- Create: `stv-trampoline/README.md`

Goal: a 1–2 KB binary that Saturn IPL will recognize as a valid cart-boot image, prints "SAROO-STV Phase 1 OK" via VDP2 text, halts.

The Saturn IPL checks for magic `"SEGA SEGASATURN "` (16 bytes) at cart start, followed by maker/product/version/date/device/region/compat/game-name and an entry point pointer. Reference: [ponut64/libyaul boot header](https://github.com/ponut64/libyaul), Mednafen `ss.cpp` bootrom source.

- [ ] **Step 1: Write the boot header**

```asm
! stv-trampoline/header.s
    .section .header, "ax"
    .global _boot_header
_boot_header:
    .ascii "SEGA SEGASATURN "       ! 16 bytes, magic
    .ascii "SEGA ENTERPRISES"       ! 16 bytes, maker
    .ascii "T-000H  V1.000"         ! 10 bytes, product number + spaces
    .space 6
    .ascii "19960101"               ! 8 bytes, date YYYYMMDD
    .ascii "CD-1/1  "               ! 10 bytes, device info
    .space 2
    .ascii "JTUE    "               ! 10 bytes, region flags (J/T/U/E)
    .space 2
    .ascii "J       "               ! 16 bytes, peripheral compat (J = control pad)
    .space 8
    .ascii "SAROO-STV Phase 1       "  ! 112 bytes, game name
    .space 88
    .long  _start                   ! 4 bytes, master SH-2 entry point
    .long  0                        ! 4 bytes, slave SH-2 entry point (unused)
    .long  _start                   ! 4 bytes, first master code
    .long  0x06002000               ! 4 bytes, stack
    .long  _start                   ! ... same for slave
    .long  0x06001000
```

**Important:** verify exact field layout against a dump of a known-good Saturn CD's first 256 bytes. Use Mednafen + save state or read it off a CUE/BIN with `xxd`.

- [ ] **Step 2: Write main.c — VDP2 text mode setup + print**

```c
// stv-trampoline/main.c
#include <stdint.h>

#define VDP2_VRAM    ((volatile uint16_t*)0x25e00000)
#define VDP2_REGS    ((volatile uint16_t*)0x25f80000)
#define VDP2_CRAM    ((volatile uint16_t*)0x25f00000)

extern const uint8_t font_8x8_rom[];  // linked-in from bin2c'd font

static void vdp2_init_text_mode(void) {
    // Minimal NBG0 text-mode setup, 8x8 cells, 40x28 plane
    VDP2_REGS[0x00 >> 1] = 0x0000;  // TVMD: 320x224 NTSC
    // ... Full setup is ~20 register writes. See Yaul or Jo Engine examples.
}

static void vdp2_print(int x, int y, const char* s) {
    volatile uint16_t* map = &VDP2_VRAM[0x20000 >> 1];  // map plane in VRAM
    while(*s) {
        map[y * 64 + x] = (uint16_t)(*s++ - ' ');
        x++;
    }
}

static void hex8(char* out, uint8_t b) {
    const char H[] = "0123456789ABCDEF";
    out[0] = H[b >> 4]; out[1] = H[b & 0xf];
}

void __attribute__((noreturn)) _start(void) {
    vdp2_init_text_mode();
    vdp2_print(2, 2, "SAROO-STV Phase 1 OK");

    // Dump ROM header bytes visibly
    volatile uint8_t* rom = (volatile uint8_t*)0x02000000;
    char line[3 * 16 + 1];
    for(int row = 0; row < 4; row++) {
        for(int col = 0; col < 16; col++) {
            hex8(&line[col * 3], rom[row * 16 + col]);
            line[col * 3 + 2] = ' ';
        }
        line[48] = 0;
        vdp2_print(2, 5 + row, line);
    }

    while(1) { asm volatile("nop"); }
}
```

- [ ] **Step 3: Write the linker script**

```
/* stv-trampoline/ldscript */
OUTPUT_FORMAT("elf32-sh")
OUTPUT_ARCH(sh)
ENTRY(_boot_header)

MEMORY {
    ROM (rx) : ORIGIN = 0x02000000, LENGTH = 4M
    RAM (rwx): ORIGIN = 0x06000000, LENGTH = 1M
}

SECTIONS {
    .header 0x02000000 : { KEEP(*(.header)) } > ROM
    .text   0x02001000 : { *(.text*) }        > ROM
    .rodata            : { *(.rodata*) }      > ROM
    .data              : AT(LOADADDR(.rodata) + SIZEOF(.rodata)) { *(.data*) } > RAM
    .bss               : { *(.bss*) *(COMMON) } > RAM
    _estack = ORIGIN(RAM) + LENGTH(RAM);
}
```

- [ ] **Step 4: Write the Makefile**

```makefile
# stv-trampoline/Makefile
CROSS  ?= sh-elf-
CC      = $(CROSS)gcc
LD      = $(CROSS)ld
OBJCOPY = $(CROSS)objcopy

CFLAGS  = -m2 -mb -Os -ffreestanding -nostdlib -Wall -Wextra
LDFLAGS = -T ldscript -nostdlib

OBJS = header.o main.o

all: trampoline.bin

trampoline.elf: $(OBJS) ldscript
	$(LD) $(LDFLAGS) $(OBJS) -o $@

trampoline.bin: trampoline.elf
	$(OBJCOPY) -O binary $< $@
	@echo "Size: $$(stat -c%s $@) bytes"

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@
%.o: %.s
	$(CC) $(CFLAGS) -c $< -o $@
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.elf *.bin
```

- [ ] **Step 5: Build and verify size < 4KB**

```bash
cd stv-trampoline && make
ls -l trampoline.bin
```

Expected: `trampoline.bin` built, size < 4096 bytes.

- [ ] **Step 6: Test in Mednafen — wrap as a CUE/BIN and see if it boots**

Since Mednafen doesn't directly load raw cart ROMs, create a minimal CUE/BIN with the trampoline placed in LBA 0 data area (this actually tests CD path, not cart path — but it verifies the Saturn-format header parses).

```bash
# Pad to 2048-byte sector alignment
dd if=trampoline.bin of=test.bin bs=2048 conv=sync
cat > test.cue << 'EOF'
FILE "test.bin" BINARY
  TRACK 01 MODE1/2048
    INDEX 01 00:00:00
EOF
mednafen test.cue
```

Expected: Mednafen boots the stub, "SAROO-STV Phase 1 OK" appears. If it doesn't, inspect the header byte-by-byte against a known-good CD dump.

- [ ] **Step 7: Commit**

```bash
git add stv-trampoline/
git commit -m "feat(trampoline): minimal Saturn-format hello stub"
```

---

## Task 6: STM32 firmware — ST-V ROM loader (SD → SDRAM)

**Files:**
- Create: `Firm_MCU/Saturn/stv_rom.h`
- Create: `Firm_MCU/Saturn/stv_rom.c`
- Modify: `Firm_MCU/Saturn/saturn_main.c` (add init/shell hook)
- Modify: `Firm_MCU/Main/shell.c` (add `stvload` command)

Goal: a `stv_rom_load(path)` function that reads a file from SD, writes it into SDRAM via the FSMC ram window (`fsmc_addr[24]==1` → SDRAM in existing FPGA), configures `ss_cs0_type=0` ROM mode, sets `ss_rom_base`, and returns.

- [ ] **Step 1: Write header**

```c
/* Firm_MCU/Saturn/stv_rom.h */
#ifndef STV_ROM_H
#define STV_ROM_H

#include <stdint.h>

typedef struct {
    uint32_t sdram_base;  // byte offset into SDRAM where ROM was loaded
    uint32_t size;        // bytes loaded
} stv_rom_info_t;

/* Load trampoline.bin (or ST-V ROM) from SD to SDRAM and switch FPGA to ROM mode.
 * Returns 0 on success, negative on error. */
int stv_rom_load(const char* path, stv_rom_info_t* out);

/* Restore FPGA to default Saturn-CD mode (ss_cs0_type=0 still, but CD block active). */
void stv_rom_unload(void);

#endif
```

- [ ] **Step 2: Write host-compile unit test (no STM32 hardware needed)**

```c
/* Firm_MCU/tests/test_stv_rom.c */
#include <stdio.h>
#include <string.h>
#include <assert.h>

/* Stub out STM32 / FatFS / FPGA — we test only pure logic. */
#define UNIT_TEST
#include "../Saturn/stv_rom.c"  /* #include directly for testing */

int main(void) {
    /* Test 1: load a small file, verify it reached SDRAM model */
    FILE* f = fopen("/tmp/test_rom.bin", "wb");
    const char data[] = "SEGA SEGASATURN HELLO";
    fwrite(data, 1, sizeof(data), f);
    fclose(f);

    stv_rom_info_t info;
    int rc = stv_rom_load("/tmp/test_rom.bin", &info);
    assert(rc == 0);
    assert(info.size == sizeof(data));
    assert(memcmp(g_mock_sdram + info.sdram_base, data, sizeof(data)) == 0);

    printf("PASS: stv_rom_load copies file contents to SDRAM\n");
    return 0;
}
```

```makefile
# Firm_MCU/tests/Makefile
CFLAGS = -DUNIT_TEST -std=c11 -Wall -Wextra -g -O0 -I..

test_stv_rom: test_stv_rom.c ../Saturn/stv_rom.c
	$(CC) $(CFLAGS) $< -o $@

test: test_stv_rom
	./test_stv_rom

clean:
	rm -f test_stv_rom
```

- [ ] **Step 3: Run, expect compile failure (stv_rom.c not yet written)**

```bash
cd Firm_MCU/tests && make test
```

Expected: compile error `No such file or directory: '../Saturn/stv_rom.c'`.

- [ ] **Step 4: Write stv_rom.c with both UNIT_TEST and production paths**

```c
/* Firm_MCU/Saturn/stv_rom.c */
#include "stv_rom.h"
#include <stdio.h>
#include <string.h>

#ifdef UNIT_TEST
/* Host mock */
#include <stdlib.h>
uint8_t g_mock_sdram[16 * 1024 * 1024];
static int mock_fpga_ctrl = 0;
static int mock_fpga_rombase = 0;

static int sdram_write(uint32_t offset, const void* data, size_t n) {
    if(offset + n > sizeof(g_mock_sdram)) return -1;
    memcpy(g_mock_sdram + offset, data, n);
    return 0;
}
static int file_read_all(const char* path, void* buf, size_t cap, size_t* out_n) {
    FILE* f = fopen(path, "rb");
    if(!f) return -1;
    *out_n = fread(buf, 1, cap, f);
    fclose(f);
    return 0;
}
static void fpga_ctrl_set(int val) { mock_fpga_ctrl = val; }
static void fpga_rombase_set(int val) { mock_fpga_rombase = val; }
#else
/* Production: FatFS + FSMC */
#include "ff.h"
extern volatile uint16_t* const FPGA_REGS;  // STM32 FSMC mapping

static int sdram_write(uint32_t offset, const void* data, size_t n) {
    /* SDRAM accessed via FSMC at fsmc_addr[24]=1 — see SAROO docs */
    volatile uint16_t* sdram_win = (volatile uint16_t*)(FSMC_BASE | 0x01000000);
    const uint16_t* src = data;
    for(size_t i = 0; i < n/2; i++) sdram_win[(offset/2) + i] = src[i];
    return 0;
}

static int file_read_all(const char* path, void* buf, size_t cap, size_t* out_n) {
    FIL f;
    if(f_open(&f, path, FA_READ) != FR_OK) return -1;
    UINT br;
    FRESULT rc = f_read(&f, buf, cap, &br);
    f_close(&f);
    *out_n = br;
    return rc == FR_OK ? 0 : -1;
}

static void fpga_ctrl_set(int val) { FPGA_REGS[0x04/2] = val; }
static void fpga_rombase_set(int val) { FPGA_REGS[0x30/2] = val; }
#endif

#define SDRAM_ROM_OFFSET (4 * 1024 * 1024)  /* 4MB into SDRAM, past CD cache */

int stv_rom_load(const char* path, stv_rom_info_t* out) {
    static uint8_t load_buf[2 * 1024 * 1024];  // 2MB stage buffer
    size_t n;
    if(file_read_all(path, load_buf, sizeof(load_buf), &n) != 0) return -1;

    if(sdram_write(SDRAM_ROM_OFFSET, load_buf, n) != 0) return -2;

    /* Set FPGA: ss_cs0_type=00 (ROM mode), ss_rom_base to 4MB / 1MB unit = 4 */
    fpga_rombase_set(4);
    fpga_ctrl_set(0x0100);  /* default + ROM mode */

    out->sdram_base = SDRAM_ROM_OFFSET;
    out->size = n;
    return 0;
}

void stv_rom_unload(void) {
    /* Reset ROM base, switch back to Bootrom default */
    fpga_rombase_set(0);
    fpga_ctrl_set(0x0100);
}
```

- [ ] **Step 5: Run host test, expect PASS**

```bash
cd Firm_MCU/tests && make test
```

Expected: `PASS: stv_rom_load copies file contents to SDRAM`.

- [ ] **Step 6: Wire into shell for on-device testing**

Modify `Firm_MCU/Main/shell.c` — add a `stvload <path>` command that calls `stv_rom_load` and prints result.

- [ ] **Step 7: Commit**

```bash
git add Firm_MCU/Saturn/stv_rom.{c,h} Firm_MCU/tests/ Firm_MCU/Main/shell.c
git commit -m "feat(mcu): stv_rom loader with host unit test"
```

---

## Task 7: Integration — real hardware bring-up

**Files:**
- Modify: `Firm_Saturn/main.c` (add "Load ST-V ROM" menu item)

Goal: flash new FPGA `.rbf` + STM32 `.bin`, copy `trampoline.bin` to SD card, boot real Saturn, see "SAROO-STV Phase 1 OK" on TV.

- [ ] **Step 1: Build FPGA bitstream**

```bash
cd FPGA
quartus_sh --flow compile SSMaster
ls -l output_files/SSMaster.rbf
```

- [ ] **Step 2: Build STM32 firmware**

Use MDK5 IDE — open `Firm_MCU/ssmaster.uvprojx`, build → produces `ssmaster.bin`.

- [ ] **Step 3: Build Firm_Saturn**

```bash
cd Firm_Saturn && make
```

Produces `ramimage.bin`.

- [ ] **Step 4: Prepare SD card**

```
/ramimage.bin                               <- new Firm_Saturn
/SAROO/update/SSMaster.rbf                  <- new FPGA bitstream
/SAROO/update/ssmaster.bin                  <- new MCU firmware
/SAROO/STV/hello/trampoline.bin             <- Phase 1 test ROM
```

- [ ] **Step 5: Power on Saturn — SAROO flashes, menu appears**

Verify base SAROO functionality still works (can load a CD image).

- [ ] **Step 6: Navigate to Load ST-V ROM → hello → trampoline.bin**

Expected: Saturn resets, VDP2 shows "SAROO-STV Phase 1 OK" and the first 64 bytes of the ROM in hex. If no display or crash, inspect:
- Serial debug via SAROO's UART (shell.c — check `stvload` output)
- SCU wait state settings (A-Bus CS0 default wait may be too short for SDRAM)

- [ ] **Step 7: Document observed behavior in docs/phase1-results.md**

Include photos of the TV output, UART log, and any bugs found.

- [ ] **Step 8: Commit**

```bash
git add docs/phase1-results.md Firm_Saturn/main.c
git commit -m "feat: Phase 1 bring-up on real Saturn hardware"
```

---

## Self-Review

Spec coverage check (against roadmap Phase 1 exit criteria):
- ✅ FPGA supports CS0 ROM mode → Task 3, 4
- ✅ STM32 loads SD ROM to SDRAM → Task 6
- ✅ Saturn-format trampoline stub → Task 5
- ✅ VDP2 prints Phase 1 OK + hex dump → Task 5 main.c
- ✅ Mednafen + real-hardware verification → Task 5 Step 6, Task 7

Known placeholders deliberately left:
- Font data for VDP2 — Task 5 references `font_8x8_rom[]` but doesn't include a font. **Fix in implementation**: either bin2c the existing `Firm_Saturn/font_8x16.h` style font, or use VDP2's built-in character generator mode with a hardcoded bit pattern for a minimal char set (ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789: -).
- Full SDRAM model (Task 2 picked option (c) simplified). If Task 7 reveals timing bugs, escalate to Micron MT48LC4M16 reference model in a new sub-task.
- FSMC driver sequences in testbench (`ss_reg_ctrl` write via FSMC) shown as comment stubs — implement per STM32 FSMC timing spec.

**This plan does NOT cover:**
- Running actual ST-V game ROMs (Phase 2+)
- Input, EEPROM, BIOS HLE (Phase 3+)
- Per-game compat (Phase 5)

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-24-stv-phase1-rom-boot.md`.

**Execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks. Best for multi-hardware-domain work where getting one task wrong silently (e.g., bad Verilog subtly miscompiles) costs a real bring-up cycle.

2. **Inline Execution** — execute tasks in this session using executing-plans, batch with checkpoints.

**Decision pending user input.** Phase 1 is estimated at 3–6 focused days for someone fluent in all three stacks (Verilog, STM32, SH-2 asm/C), or 1–2 weeks for someone learning as they go. Task 2 (SDRAM model) and Task 7 (bring-up debug) are the highest-variance items.
