// Simulation stub for Altera altpll megafunction.
// Real module (mainpll.v) generates mclk=100MHz and sdclk from 50MHz in.
// For simulation, we pass through and pretend locked immediately.

`timescale 1ns/1ps

module mainpll(
    input  wire inclk0,
    output wire c0,
    output wire c1,
    output wire locked
);
    assign c0 = inclk0;  // mclk stand-in (matches 50MHz testbench drive)
    assign c1 = inclk0;  // sdclk stand-in
    assign locked = 1'b1;
endmodule
