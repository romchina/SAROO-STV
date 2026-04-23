// Task 1: minimal testbench that compiles the DUT, releases reset, drives a
// CS0 read cycle, and exits cleanly. Does NOT assert data values yet
// (Task 2 wires up a real SDRAM model + checks).

`timescale 1ns/1ps

module tb_cs0_rom;

    // ---------- clocks / reset ----------
    reg CLK_50M = 0;
    reg SS_MCLK = 0;
    reg SS_RST  = 0;
    always #10 CLK_50M = ~CLK_50M;   // 50 MHz
    always #17 SS_MCLK = ~SS_MCLK;   // ~29 MHz (approx Saturn master clock)

    // ---------- Saturn A-Bus stimulus ----------
    reg  [23:0] SS_ADDR = 24'h0;
    reg  [15:0] ss_data_drv = 16'hzzzz;
    wire [15:0] SS_DATA;
    assign SS_DATA = ss_data_drv;
    reg SS_CS0 = 1, SS_CS1 = 1, SS_CS2 = 1;
    reg SS_RD  = 1, SS_WR0 = 1, SS_WR1 = 1;
    wire SS_WAIT;

    // ---------- SDRAM signals ----------
    wire SD_CKE, SD_CLK, SD_CS_n, SD_WE_n, SD_CAS_n, SD_RAS_n;
    wire [12:0] SD_ADDR;
    wire [ 1:0] SD_BA, SD_DQM;
    wire [15:0] SD_DQ;

    // ---------- STM32 FSMC stubs (idle) ----------
    reg ST_CLK = 0, ST_CS = 1, ST_RD = 1, ST_WR = 1;
    reg ST_ALE = 0, ST_BL0 = 1, ST_BL1 = 1;
    reg  [ 7:0] ST_ADDR = 0;
    reg  [15:0] st_ad_drv = 16'hzzzz;
    wire [15:0] ST_AD;
    assign ST_AD = st_ad_drv;
    wire ST_WAIT;
    reg ST_GPIO0 = 0;   // NRESET (active low -> held at 0 = in reset)

    // ---------- DUT ----------
    SSMaster dut(
        .CLK_50M(CLK_50M),
        .SD_CKE(SD_CKE), .SD_CLK(SD_CLK), .SD_CS(SD_CS_n),
        .SD_WE(SD_WE_n), .SD_CAS(SD_CAS_n), .SD_RAS(SD_RAS_n),
        .SD_ADDR(SD_ADDR), .SD_BA(SD_BA), .SD_DQM(SD_DQM), .SD_DQ(SD_DQ),
        .PSRAM_CS(),
        .SS_MCLK(SS_MCLK), .SS_RST(SS_RST),
        .SS_SCLK(1'b0), .SS_SSEL(), .SS_BCK(), .SS_LRCK(), .SS_SD(),
        .SS_FC0(1'b0), .SS_FC1(1'b0),
        .SS_TIM0(1'b0), .SS_TIM1(1'b0), .SS_TIM2(1'b0),
        .SS_AAS(1'b0),
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

    // ---------- SDRAM tie-off (Task 1 only) ----------
    sdram_tie_off sdram(
        .CKE(SD_CKE), .CLK(SD_CLK), .CS_n(SD_CS_n),
        .RAS_n(SD_RAS_n), .CAS_n(SD_CAS_n), .WE_n(SD_WE_n),
        .A(SD_ADDR), .BA(SD_BA), .DQM(SD_DQM), .DQ(SD_DQ)
    );

    // ---------- test sequence ----------
    initial begin
        $dumpfile("tb_cs0_rom.vcd");
        $dumpvars(0, tb_cs0_rom);

        $display("[TB] boot");

        // hold reset for a few hundred ns
        #500 ST_GPIO0 = 1'b1;   // release NRESET
        $display("[TB] NRESET released at t=%0t", $time);

        // wait for FPGA to settle
        #500

        // --- drive one CS0 read cycle at Saturn address 0x02000000 ---
        SS_ADDR = 24'h000000;
        SS_CS0  = 1'b0;
        SS_RD   = 1'b0;
        #200
        SS_CS0  = 1'b1;
        SS_RD   = 1'b1;
        $display("[TB] CS0 read cycle fired at t=%0t", $time);

        // settle then finish
        #1000 $display("[TB] done");
        $finish;
    end

    // safety watchdog — prevent infinite sims
    initial begin
        #100000
        $display("[TB] watchdog timeout");
        $finish;
    end

endmodule
