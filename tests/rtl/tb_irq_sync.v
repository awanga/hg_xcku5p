// SPDX-License-Identifier: MIT
// Expected from the contract in irq_sync.v: every input bit appears at the output exactly two destination clocks later,
// including a pulse of two destination cycles, and bits do not affect each other.
`timescale 1ns / 1ps
module tb_irq_sync;
    reg clk = 1'b0;
    reg [2:0] d = 3'b000;
    wire [2:0] q;
    always #1.5 clk = ~clk;
    irq_sync #(.W(3)) dut (.clk(clk), .d(d), .q(q));
    integer errors = 0, checks = 0, i;
    reg [2:0] hist0, hist1;
    task check(input [2:0] got, input [2:0] want, input [255:0] what);
        begin
            checks = checks + 1;
            if (got !== want) begin errors = errors + 1; $display("FAIL: %0s got %b want %b (t=%0t)", what, got, want, $time); end
        end
    endtask
    initial begin
        repeat (4) @(posedge clk);
        // drive a sequence (new value every cycle at negedge) and compare against the input two cycles earlier
        hist0 = 3'b000; hist1 = 3'b000;
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk);
            check(q, hist1, "output equals input two clocks earlier");
            hist1 = hist0;
            d = (i % 7 == 0) ? 3'b001 : (i % 5 == 0) ? 3'b110 : (i % 3 == 0) ? 3'b010 : 3'b000;
            hist0 = d;
        end
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
