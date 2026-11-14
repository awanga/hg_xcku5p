// SPDX-License-Identifier: MIT
// Expected from the contract in gmii_rx_reg.v: the output equals the input one clock earlier, for every bit independently.
`timescale 1ns / 1ps
module tb_gmii_rx_reg;
    reg clk = 1'b0;
    reg [9:0] d = 10'd0;
    wire [9:0] q;
    always #4 clk = ~clk;
    gmii_rx_reg #(.W(10)) dut (.clk(clk), .d(d), .q(q));
    integer errors = 0, checks = 0, i;
    reg [9:0] prev;
    // d changes 1 ns after a rising edge; q is checked 2 ns after that edge. A registered q still shows the value d had at the
    // edge; a combinational path would already show the new d.
    initial begin
        repeat (3) @(posedge clk);
        prev = 10'd0;
        for (i = 0; i < 80; i = i + 1) begin
            @(posedge clk);
            prev = d; // value captured at this edge
            #1 d = (i % 3 == 0) ? (10'd1 << (i % 10)) : ((i * 37 + 11) & 10'h3ff);
            #1 checks = checks + 1;
            if (q !== prev) begin errors = errors + 1; $display("FAIL: got %b want %b (t=%0t)", q, prev, $time); end
        end
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
