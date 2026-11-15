// SPDX-License-Identifier: MIT
// Behavioural models of the Xilinx primitives that the generated LiteEth core instantiates, for Icarus/Verilator.
module BUFG (input I, output O);
    assign O = I;
endmodule

module ODDRE1 (input C, input D1, input D2, input SR, output Q);
    // SAME_EDGE: both inputs are sampled at the rising edge; D1 is driven during the high phase, D2 during the low phase.
    reg d1q = 1'b0, d2q = 1'b0;
    always @(posedge C) begin
        d1q <= D1;
        d2q <= D2;
    end
    assign Q = C ? d1q : d2q;
endmodule

module OBUFDS (input I, output O, output OB);
    assign O = I;
    assign OB = ~I;
endmodule

module FDPE #(parameter INIT = 1'b1) (input C, input CE, input D, input PRE, output reg Q);
    initial Q = INIT;
    always @(posedge C or posedge PRE)
        if (PRE) Q <= 1'b1;
        else if (CE) Q <= D;
endmodule

module IOBUF (input I, input T, inout IO, output O);
    assign IO = T ? 1'bz : I;
    assign O = IO;
endmodule
