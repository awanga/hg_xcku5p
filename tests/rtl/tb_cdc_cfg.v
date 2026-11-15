// SPDX-License-Identifier: MIT
// cdc_cfg between unrelated clocks (periods 3.0 ns and 10.0 ns, both directions of speed ratio via parameters). The source drives complementary
// 32-bit words (so a word torn between two values cannot equal either); the destination output must only ever show a value that was presented, must
// end at the last one, and must be zero in reset. Expected values are the list of presented words, not read from the DUT.
`timescale 1ps / 1ps
module tb_cdc_cfg;
    parameter SRC_HALF = 1500, DST_HALF = 5000;
    reg src_clk = 1'b0, dst_clk = 1'b0, src_rst_n = 1'b0, dst_rst_n = 1'b0;
    always #SRC_HALF src_clk = ~src_clk;
    always #DST_HALF dst_clk = ~dst_clk;
    reg  [31:0] d = 32'd0;
    wire [31:0] q;
    cdc_cfg #(.W(32)) dut (.src_clk(src_clk), .src_rst_n(src_rst_n), .d(d), .dst_clk(dst_clk), .dst_rst_n(dst_rst_n), .q(q));

    reg [31:0] words [0:7];
    integer errors = 0, checks = 0, i, j, seen;
    reg legal;
    // monitor: every value of q after the first reset release must be 0 or one of the presented words
    reg armed = 1'b0;
    always @(posedge dst_clk) if (armed) begin
        legal = (q === 32'd0);
        for (j = 0; j < 8; j = j + 1) if (q === words[j]) legal = 1'b1;
        if (!legal) begin errors = errors + 1; $display("FAIL torn or unknown value %h at %0t", q, $time); end
    end
    task expect_(input [255:0] what, input [31:0] got, input [31:0] want);
        begin checks = checks + 1; if (got !== want) begin errors = errors + 1; $display("FAIL %0s: got %h want %h", what, got, want); end end
    endtask
    initial begin
        words[0] = 32'hA5A5_A5A5; words[1] = 32'h5A5A_5A5A; words[2] = 32'hFFFF_0000; words[3] = 32'h0000_FFFF;
        words[4] = 32'h1234_5678; words[5] = 32'hEDCB_A987; words[6] = 32'h8000_0001; words[7] = 32'h7FFF_FFFE;
        #50000 src_rst_n = 1'b1; dst_rst_n = 1'b1; armed = 1'b1;
        #100000;
        expect_("zero after reset", q, 32'd0);
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge src_clk); d = words[i];
            #400000;
            expect_("value arrives", q, words[i]);
        end
        // a burst of changes faster than the transfer: only presented values may show, and the last must arrive
        for (i = 0; i < 8; i = i + 1) begin @(negedge src_clk); d = words[7 - i]; end
        #600000;
        expect_("last value of a burst arrives", q, words[0]);
        // a reset in the destination domain forces the output to zero
        dst_rst_n = 1'b0; #50000;
        expect_("destination reset zeroes q", q, 32'd0);
        dst_rst_n = 1'b1; #100000;
        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (errors == 0 && checks > 8) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
