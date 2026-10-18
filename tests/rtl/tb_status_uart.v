// SPDX-License-Identifier: MIT
// Decodes the serial line at the bit rate and compares the received line with the expected text.
`timescale 1ns / 1ps
module tb_status_uart;
    parameter CPB = 16;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #2.5 clk = ~clk;
    wire tx;
    status_uart #(.CLKS_PER_BIT(CPB), .INTERVAL(2000)) dut (
        .clk(clk), .rst_n(rst_n), .calib(1'b1), .pass(32'h0000001A), .err(32'h00000000),
        .wr(32'hDEADBEEF), .rd(32'h0123ABCD), .tx(tx));

    reg [8*44-1:0] line; // first char in the top byte
    integer n = 0;
    integer errors = 0;
    integer k;
    reg [7:0] b;
    reg [8*44-1:0] want;
    initial begin
        want = "C1 P0000001A E00000000 WDEADBEEF R0123ABCD";
        want = {want[8*42-1:0], 8'h0D, 8'h0A};
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        // receive 44 characters
        while (n < 44) begin
            @(negedge tx);
            repeat (CPB + CPB / 2) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = tx;
                repeat (CPB) @(posedge clk);
            end
            if (tx !== 1'b1) begin
                errors = errors + 1;
                $display("framing error at char %0d", n);
            end
            line = {line[8*43-1:0], b};
            n = n + 1;
        end
        if (line !== want) begin
            errors = errors + 1;
            $display("got  %0s", line);
            $display("want %0s", want);
        end
        $display("TBRESULT chars=%0d errors=%0d %s", n, errors, (errors == 0 && n == 44) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin
        #5000000;
        $display("TBRESULT timeout FAIL");
        $finish;
    end
endmodule
