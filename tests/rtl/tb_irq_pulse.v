// SPDX-License-Identifier: MIT
// Expected pulse shape from the contract: one pulse of HOLD cycles per rising edge of the level input, none while it stays high.
`timescale 1ns / 1ps
module tb_irq_pulse;
    reg clk = 1'b0, rst_n = 1'b0, level = 1'b0;
    wire pulse;
    always #5 clk = ~clk;
    irq_pulse #(.HOLD(4)) dut (.clk(clk), .rst_n(rst_n), .level(level), .pulse(pulse));
    integer errors = 0, checks = 0, n, i;
    task check(input cond, input [255:0] what);
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s (t=%0t)", what, $time); end
        end
    endtask
    // count pulse-high cycles over the next N clocks
    task count(input integer cycles);
        begin
            n = 0;
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk); #1;
                if (pulse) n = n + 1;
            end
        end
    endtask
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        count(5); check(n == 0, "no pulse while level is low");
        @(negedge clk); level = 1'b1;
        count(20); check(n == 4, "one 4-cycle pulse for a held-high level");
        @(negedge clk); level = 1'b0;
        count(10); check(n == 0, "no pulse on the falling edge");
        @(negedge clk); level = 1'b1;
        count(10); check(n == 4, "second rising edge gives a new pulse");
        // glitch: level drops and rises again while the pulse is still active restarts the hold
        @(negedge clk); level = 1'b0; @(negedge clk); level = 1'b1;
        count(10); check(n >= 4 && n <= 7, "retrigger inside the pulse keeps it bounded");
        @(negedge clk); level = 1'b0;
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
