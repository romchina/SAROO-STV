// Simplified behavioral SDR SDRAM model for Phase 1 sim.
//
// Matches tsdram.v's target device (MT48LC32M16A2 family):
//   4 banks x 2^ROW_BITS rows x 2^COL_BITS cols, 16-bit DQ
//   CL=2, BL=4 (read burst length)
//
// What this model DOES:
//   - Decode command bits {CS_n, RAS_n, CAS_n, WE_n}:
//       0011 ACTIVE, 0101 READ, 0100 WRITE, others ignored
//   - Capture per-bank row on ACTIVE
//   - Schedule BL-word burst onto DQ with CL-cycle latency after READ
//   - Commit one word on WRITE
//   - Provide a backdoor load_word() task + $readmemh INIT_FILE
//
// What this model does NOT do:
//   - Timing enforcement (tRCD, tRAS, tRP, tRC, refresh intervals)
//   - Mode register programming (we hardcode CL=2, BL=4)
//   - Auto-precharge flag handling (A10 during READ/WRITE is ignored)
//   - DQM masking on writes (DQM is ignored for the write path)
//
// Backed by a 2 MB flat word array. Saturn ROM tests only hit low
// addresses so this window is sufficient. Increase MEM_WORDS if a
// future test exercises larger offsets.

`timescale 1ns/1ps

module sdram_model #(
    parameter integer CL        = 2,
    parameter integer BL        = 4,
    parameter integer MEM_WORDS = 1024*1024,           // 2 MB word array
    parameter         INIT_FILE = ""                   // optional $readmemh source
) (
    input  wire         CKE,
    input  wire         CLK,
    input  wire         CS_n,
    input  wire         RAS_n,
    input  wire         CAS_n,
    input  wire         WE_n,
    input  wire [12:0]  A,
    input  wire [ 1:0]  BA,
    input  wire [ 1:0]  DQM,
    inout  wire [15:0]  DQ
);

    // Storage
    reg [15:0] mem [0:MEM_WORDS-1];
    reg [12:0] row [0:3];

    // Command decode
    wire [3:0] cmd      = {CS_n, RAS_n, CAS_n, WE_n};
    wire       is_active  = (cmd == 4'b0011);
    wire       is_read    = (cmd == 4'b0101);
    wire       is_write   = (cmd == 4'b0100);

    // Read-burst pipeline (depth = CL + BL + 1 = 7 stages to be safe)
    localparam integer PIPE_DEPTH = 7;
    reg [PIPE_DEPTH-1:0] rd_oe_pipe;
    reg [15:0]           rd_data_pipe [0:PIPE_DEPTH-1];

    integer i;

    // Address flattening: mem[ {row[9:0], A[9:0]} ] — 20 bits = 1M words.
    // Bank bits and upper row bits are ignored for simplicity.
    function [19:0] word_addr(input [1:0] ba, input [12:0] r, input [9:0] col);
        word_addr = {r[9:0], col};
    endfunction

    always @(posedge CLK) begin
        if(!CKE) begin
            rd_oe_pipe <= {PIPE_DEPTH{1'b0}};
        end else begin
            // ACTIVE — latch row for that bank
            if(is_active) begin
                row[BA] <= A;
            end

            // WRITE — commit one word immediately (DQM ignored)
            if(is_write) begin
                mem[word_addr(BA, row[BA], A[9:0])] <= DQ;
            end

            // Shift read pipeline one slot toward output
            for(i = 0; i < PIPE_DEPTH-1; i = i + 1) begin
                rd_data_pipe[i] <= rd_data_pipe[i+1];
            end
            rd_data_pipe[PIPE_DEPTH-1] <= 16'h0000;
            rd_oe_pipe <= {1'b0, rd_oe_pipe[PIPE_DEPTH-1:1]};

            // READ — schedule BL words starting at CL cycles from now.
            // Note: this overwrites the shifted-by-1 values at those slots.
            if(is_read) begin
                for(i = 0; i < BL; i = i + 1) begin
                    rd_oe_pipe[CL + i - 1]      <= 1'b1;
                    rd_data_pipe[CL + i - 1]    <= mem[word_addr(BA, row[BA], A[9:0] + i[9:0])];
                end
            end
        end
    end

    // Drive DQ combinationally from pipeline stage 0.
    // (Registering would put DQ one cycle too late vs tsdram.v's
    //  CAS-latency 2 expectation — tsdram samples sd_din on the edge
    //  data_valid asserts; the pre-edge DQ value must already be valid.)
    assign DQ = rd_oe_pipe[0] ? rd_data_pipe[0] : 16'hzzzz;

    // Init
    initial begin
        for(i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 16'h0000;
        if(INIT_FILE != "") $readmemh(INIT_FILE, mem);
        rd_oe_pipe = {PIPE_DEPTH{1'b0}};
        for(i = 0; i < PIPE_DEPTH; i = i + 1) rd_data_pipe[i] = 16'h0000;
        for(i = 0; i < 4; i = i + 1) row[i] = 13'h0000;
    end

    // Backdoor load for testbenches
    task load_word(input [19:0] addr, input [15:0] val);
        mem[addr] = val;
    endtask

endmodule
