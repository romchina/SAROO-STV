// Task 2 testbench: wire up the behavioral SDRAM model, pre-load the
// Saturn cart boot magic ("SEGA SEGASATURN "), release reset, wait for
// tsdram.v POR sequence to finish, drive a CS0 read, and assert the
// returned word matches the magic.
//
// Byte-order note: SSMaster.v swaps bytes between the Saturn side
// (big-endian) and the SDRAM side. "SE" (0x53 0x45) shows up in SDRAM
// as mem[0] = 0x4553.

`timescale 1ns/1ps

module tb_cs0_rom;

    // ---------- clocks / reset ----------
    reg CLK_50M = 0;
    reg SS_MCLK = 0;
    reg SS_RST  = 0;
    always #10 CLK_50M = ~CLK_50M;   // 50 MHz
    always #17 SS_MCLK = ~SS_MCLK;   // ~29 MHz (Saturn-side strobe)

    // ---------- Saturn A-Bus stimulus ----------
    reg  [23:0] SS_ADDR = 24'h0;
    reg  [15:0] ss_data_drv = 16'hzzzz;
    wire [15:0] SS_DATA;
    assign SS_DATA = ss_data_drv;
    reg SS_CS0 = 1, SS_CS1 = 1, SS_CS2 = 1;
    reg SS_RD  = 1, SS_WR0 = 1, SS_WR1 = 1;
    wire SS_WAIT;

    // ---------- SDRAM signals ----------
    wire        SD_CKE, SD_CLK, SD_CS_n, SD_WE_n, SD_CAS_n, SD_RAS_n;
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
    reg ST_GPIO0 = 0;

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

    // ---------- Behavioral SDRAM ----------
    sdram_model sdram(
        .CKE(SD_CKE), .CLK(SD_CLK), .CS_n(SD_CS_n),
        .RAS_n(SD_RAS_n), .CAS_n(SD_CAS_n), .WE_n(SD_WE_n),
        .A(SD_ADDR), .BA(SD_BA), .DQM(SD_DQM), .DQ(SD_DQ)
    );

    // ---------- helpers ----------
    integer fail_count = 0;

    // Saturn-side write cycle (both byte enables active).
    task ss_write16;
        input [23:0] addr;
        input [15:0] value;
        integer k;
        begin
            @(posedge CLK_50M);
            SS_ADDR     = addr;
            ss_data_drv = value;
            SS_CS0      = 1'b0;
            SS_WR0      = 1'b0;
            SS_WR1      = 1'b0;
            repeat(6) @(posedge CLK_50M);
            k = 0;
            while(SS_WAIT !== 1'b1 && k < 200) begin
                @(posedge CLK_50M);
                k = k + 1;
            end
            @(posedge CLK_50M);
            SS_CS0 = 1'b1;
            SS_WR0 = 1'b1;
            SS_WR1 = 1'b1;
            ss_data_drv = 16'hzzzz;
            repeat(6) @(posedge CLK_50M);
        end
    endtask

    // Saturn-side read cycle. Uses blocking assignments so stimulus
    // takes effect immediately and the WAIT poll sees fresh state.
    task ss_read16;
        input  [23:0] addr;
        output [15:0] data;
        integer k;
        begin
            @(posedge CLK_50M);
            SS_ADDR = addr;
            SS_CS0  = 1'b0;
            SS_RD   = 1'b0;
            // Let synchronizer notice (it's a 3-stage shift on mclk)
            repeat(6) @(posedge CLK_50M);
            // Wait for WAIT to rise (fetch done / cache hit)
            k = 0;
            while(SS_WAIT !== 1'b1 && k < 200) begin
                @(posedge CLK_50M);
                k = k + 1;
            end
            if(k >= 200) $display("[TB] WARN read timeout @ addr=0x%06x t=%0t", addr, $time);
            // Sample while CS0+RD still asserted (SS_DATA mux gated by these)
            @(posedge CLK_50M);
            data = SS_DATA;
            SS_CS0 = 1'b1;
            SS_RD  = 1'b1;
            repeat(6) @(posedge CLK_50M);
        end
    endtask

    task check_eq16;
        input [127:0] label;
        input [15:0]  actual;
        input [15:0]  expected;
        begin
            if(actual === expected) begin
                $display("[TB] PASS %0s: got 0x%04x", label, actual);
            end else begin
                $display("[TB] FAIL %0s: got 0x%04x, expected 0x%04x",
                         label, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ---------- test sequence ----------
    reg [15:0] got;

    initial begin
        $dumpfile("tb_cs0_rom.vcd");
        $dumpvars(0, tb_cs0_rom);
        $display("[TB] boot");

        // Pre-load magic bytes into SDRAM. After SSMaster byte-swap,
        // mem[0]=0x4553 is what SH-2 reads as 0x5345 ("SE") at
        // Saturn address 0x02000000.
        sdram.mem[0] = 16'h4553;  // "SE" (Saturn reads 'SE')
        sdram.mem[1] = 16'h4147;  // "GA"
        sdram.mem[2] = 16'h5320;  // " S"
        sdram.mem[3] = 16'h4745;  // "EG"
        sdram.mem[4] = 16'h5341;  // "AS"
        sdram.mem[5] = 16'h5441;  // "AT"
        sdram.mem[6] = 16'h5255;  // "UR"
        sdram.mem[7] = 16'h204e;  // "N "

        // release NRESET
        #500 ST_GPIO0 = 1'b1;
        $display("[TB] NRESET released at t=%0t", $time);

        // Wait for tsdram.v POR sequence: tPOR_count = 20100 clocks ~= 402us
        // plus CKE-assert+precharge+refresh+LMR latency. Be generous.
        #600000;
        $display("[TB] waited for SDRAM POR, t=%0t", $time);

        // SS_ADDR is byte-addressed (ss_ram_addr[0] is byte-in-word,
        // cachebus uses addr[2:1] to pick word-in-line).
        // Word 0 = byte 0x00: "SE"=0x5345
        ss_read16(24'h000000, got);
        check_eq16("CS0 read byte 0x0 (expect 'SE'=0x5345)", got, 16'h5345);

        // Word 1 = byte 0x02: "GA"=0x4741
        ss_read16(24'h000002, got);
        check_eq16("CS0 read byte 0x2 (expect 'GA'=0x4741)", got, 16'h4741);

        // Word 2 = byte 0x04: " S"=0x2053
        ss_read16(24'h000004, got);
        check_eq16("CS0 read byte 0x4 (expect ' S'=0x2053)", got, 16'h2053);

        // Word 3 = byte 0x06: "EG"=0x4547
        ss_read16(24'h000006, got);
        check_eq16("CS0 read byte 0x6 (expect 'EG'=0x4547)", got, 16'h4547);

        // Word from next cache line — byte 0x08: "AS"=0x4153 — forces miss
        ss_read16(24'h000008, got);
        check_eq16("CS0 read byte 0x8 (expect 'AS'=0x4153 new line)", got, 16'h4153);

        // --- Task 3 test: ROM mode is read-only ---
        // ss_cs0_type defaults to 2'b00 after reset (ss_reg_ctrl[13:12]=00),
        // so we're already in ROM mode. Attempt a write to byte 0x0 and
        // verify the old value is still there on re-read.
        $display("[TB] attempting Saturn-side write in ROM mode...");
        ss_write16(24'h000000, 16'hBEEF);
        // Re-read the same word — should still be 0x5345, NOT 0xBEEF
        ss_read16(24'h000000, got);
        check_eq16("ROM mode blocks CS0 write (expect unchanged 0x5345)", got, 16'h5345);

        // Second write test on the already-hot cache line
        // Byte 0x0a -> "AT" (byte 10='A', 11='T') Saturn BE => 0x4154
        ss_write16(24'h00000a, 16'hDEAD);
        ss_read16(24'h00000a, got);
        check_eq16("ROM mode blocks CS0 write (expect unchanged 0x4154)", got, 16'h4154);

        #2000
        if(fail_count == 0) $display("[TB] ALL PASS");
        else                $display("[TB] %0d FAILURES", fail_count);

        $finish;
    end

    // safety watchdog
    initial begin
        #2000000  // 2 ms — covers POR + several reads
        $display("[TB] watchdog timeout");
        $finish;
    end

endmodule
