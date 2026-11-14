// SPDX-License-Identifier: MIT
// Behavioural models of the Xilinx primitives that the generated LiteEth core instantiates, for Icarus/Verilator.
module BUFG (input I, output O);
    assign O = I;
endmodule

module ODDRE1 (input C, input D1, input D2, input SR, output Q);
    // SAME_EDGE with D2 = 0 and D1 = 1: Q follows C (forwarded clock). Only that use exists in the core.
    assign Q = C ? D1 : D2;
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
