// Simulation stub for Altera scfifo megafunction (cdcfifo).
// Real module: 2048-entry SCFIFO. For Phase 1 sim we don't exercise the CDC
// path, so a 16-entry ring buffer is plenty.

`timescale 1ns/1ps

module cdcfifo(
    input  wire         sclr,
    input  wire         clock,
    input  wire         rdreq,
    output wire [15:0]  q,
    input  wire         wrreq,
    input  wire [15:0]  data,
    output wire         empty,
    output wire [10:0]  usedw,
    output wire         full
);
    reg [15:0] mem [0:15];
    reg [ 4:0] wp, rp;
    wire [4:0] used = wp - rp;

    always @(posedge clock) begin
        if(sclr) begin
            wp <= 5'd0;
            rp <= 5'd0;
        end else begin
            if(wrreq && !full) begin
                mem[wp[3:0]] <= data;
                wp <= wp + 5'd1;
            end
            if(rdreq && !empty) begin
                rp <= rp + 5'd1;
            end
        end
    end

    assign q     = mem[rp[3:0]];
    assign empty = (used == 5'd0);
    assign full  = (used == 5'd16);
    assign usedw = {6'd0, used};
endmodule
