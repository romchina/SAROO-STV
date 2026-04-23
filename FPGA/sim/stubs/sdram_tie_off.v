// Task 1: tie-off SDRAM model.
// Just holds DQ at high-Z so SSMaster doesn't see Xs.
// Task 2 replaces this with a real SDRAM behavioral model.

`timescale 1ns/1ps

module sdram_tie_off(
    input  wire CKE,
    input  wire CLK,
    input  wire CS_n,
    input  wire RAS_n,
    input  wire CAS_n,
    input  wire WE_n,
    input  wire [12:0] A,
    input  wire [ 1:0] BA,
    input  wire [ 1:0] DQM,
    inout  wire [15:0] DQ
);
    assign DQ = 16'hzzzz;
endmodule
