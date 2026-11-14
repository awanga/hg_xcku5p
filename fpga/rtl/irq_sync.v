// SPDX-License-Identifier: MIT
// Two-flop synchronizer for interrupt lines that come from another clock domain. The PLIC gateway samples its source in two
// flops (pending and wait-for-completion); with an asynchronous source they can capture different values near a clock edge,
// and "waiting without pending" blocks that interrupt for good. Input pulses must last longer than one destination period.
module irq_sync #(
    parameter W = 3
) (
    input  wire         clk,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);
    (* ASYNC_REG = "TRUE" *) reg [W-1:0] s1 = {W{1'b0}};
    (* ASYNC_REG = "TRUE" *) reg [W-1:0] s2 = {W{1'b0}};
    assign q = s2;

    always @(posedge clk) begin
        s1 <= d;
        s2 <= s1;
    end
endmodule
