// SPDX-License-Identifier: MIT
// Independent model: the DVI 1.0 *decoder*. Every data word must decode back to the input byte, control words must equal the four literal codes of the
// specification, and the cumulative disparity of the stream (ones minus zeros over all bits sent) must stay bounded; a never-inverting encoder drifts.
`timescale 1ns / 1ps
module tb_tmds_encoder;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg [7:0] d = 8'd0;
    reg [1:0] c = 2'd0;
    reg       de = 1'b0;
    wire [9:0] q;
    tmds_encoder dut (.clk(clk), .d(d), .c(c), .de(de), .q(q));

    integer errors = 0, checks = 0, i, k, seed = 7;
    integer cum = 0, maxabs = 0, ones;
    reg [7:0] x, dec;
    reg [7:0] exp_d;
    reg [1:0] exp_c;
    reg       exp_de;
    reg [7:0] prev_d;

    function [7:0] decode;  // DVI 1.0 decode, written from the spec's inverse transform
        input [9:0] w;
        reg [7:0] y;
        integer j;
        begin
            y = w[9] ? ~w[7:0] : w[7:0];
            decode[0] = y[0];
            for (j = 1; j < 8; j = j + 1) decode[j] = w[8] ? (y[j] ^ y[j-1]) : ~(y[j] ^ y[j-1]);
        end
    endfunction

    task step;
        input [7:0] dd;
        input [1:0] cc;
        input dee;
        begin
            @(negedge clk);
            d = dd; c = cc; de = dee;
            exp_d = dd; exp_c = cc; exp_de = dee;
            @(posedge clk);
            #1;
            checks = checks + 1;
            if (dee) begin
                if (decode(q) !== dd) begin errors = errors + 1; $display("FAIL data %h -> %b -> %h", dd, q, decode(q)); end
                ones = 0;
                for (k = 0; k < 10; k = k + 1) ones = ones + q[k];
                cum = cum + 2 * ones - 10;
            end else begin
                cum = 0;
                case (cc)
                    2'b00: if (q !== 10'b1101010100) begin errors = errors + 1; $display("FAIL ctl0 %b", q); end
                    2'b01: if (q !== 10'b0010101011) begin errors = errors + 1; $display("FAIL ctl1 %b", q); end
                    2'b10: if (q !== 10'b0101010100) begin errors = errors + 1; $display("FAIL ctl2 %b", q); end
                    default: if (q !== 10'b1010101011) begin errors = errors + 1; $display("FAIL ctl3 %b", q); end
                endcase
            end
            if (cum > maxabs) maxabs = cum;
            if (-cum > maxabs) maxabs = -cum;
        end
    endtask

    // golden vectors: 64 consecutive data words (from de = 0, disparity 0) encoded by a separate reference implementation of the DVI 1.0 algorithm
    reg [7:0] gold_d [0:63];
    reg [9:0] gold_q [0:63];
    initial begin
        gold_d[0] = 8'h00; gold_q[0] = 10'h100;
        gold_d[1] = 8'hFF; gold_q[1] = 10'h0FF;
        gold_d[2] = 8'h0F; gold_q[2] = 10'h3FA;
        gold_d[3] = 8'hF0; gold_q[3] = 10'h205;
        gold_d[4] = 8'h01; gold_q[4] = 10'h1FF;
        gold_d[5] = 8'h80; gold_q[5] = 10'h180;
        gold_d[6] = 8'h55; gold_q[6] = 10'h133;
        gold_d[7] = 8'hAA; gold_q[7] = 10'h233;
        gold_d[8] = 8'h10; gold_q[8] = 10'h1F0;
        gold_d[9] = 8'h3C; gold_q[9] = 10'h241;
        gold_d[10] = 8'hC3; gold_q[10] = 10'h3BE;
        gold_d[11] = 8'h7E; gold_q[11] = 10'h080;
        gold_d[12] = 8'h81; gold_q[12] = 10'h17F;
        gold_d[13] = 8'hFE; gold_q[13] = 10'h000;
        gold_d[14] = 8'h0E; gold_q[14] = 10'h1FA;
        gold_d[15] = 8'hE0; gold_q[15] = 10'h35F;
        gold_d[16] = 8'h82; gold_q[16] = 10'h381;
        gold_d[17] = 8'hB7; gold_q[17] = 10'h238;
        gold_d[18] = 8'h0E; gold_q[18] = 10'h1FA;
        gold_d[19] = 8'hEE; gold_q[19] = 10'h20F;
        gold_d[20] = 8'h7F; gold_q[20] = 10'h280;
        gold_d[21] = 8'h1A; gold_q[21] = 10'h1F6;
        gold_d[22] = 8'h50; gold_q[22] = 10'h130;
        gold_d[23] = 8'h39; gold_q[23] = 10'h117;
        gold_d[24] = 8'hBE; gold_q[24] = 10'h23F;
        gold_d[25] = 8'hF0; gold_q[25] = 10'h205;
        gold_d[26] = 8'h7E; gold_q[26] = 10'h27F;
        gold_d[27] = 8'hC2; gold_q[27] = 10'h341;
        gold_d[28] = 8'h34; gold_q[28] = 10'h1EC;
        gold_d[29] = 8'h7F; gold_q[29] = 10'h280;
        gold_d[30] = 8'h06; gold_q[30] = 10'h3FD;
        gold_d[31] = 8'h6E; gold_q[31] = 10'h070;
        gold_d[32] = 8'hD0; gold_q[32] = 10'h1B0;
        gold_d[33] = 8'h8F; gold_q[33] = 10'h02F;
        gold_d[34] = 8'h5D; gold_q[34] = 10'h29E;
        gold_d[35] = 8'hC7; gold_q[35] = 10'h2E8;
        gold_d[36] = 8'h51; gold_q[36] = 10'h1CF;
        gold_d[37] = 8'h24; gold_q[37] = 10'h11C;
        gold_d[38] = 8'h47; gold_q[38] = 10'h3C2;
        gold_d[39] = 8'hE3; gold_q[39] = 10'h00B;
        gold_d[40] = 8'h40; gold_q[40] = 10'h33F;
        gold_d[41] = 8'h43; gold_q[41] = 10'h1C1;
        gold_d[42] = 8'h00; gold_q[42] = 10'h100;
        gold_d[43] = 8'h02; gold_q[43] = 10'h1FE;
        gold_d[44] = 8'h6B; gold_q[44] = 10'h28C;
        gold_d[45] = 8'h6E; gold_q[45] = 10'h28F;
        gold_d[46] = 8'h54; gold_q[46] = 10'h1CC;
        gold_d[47] = 8'h55; gold_q[47] = 10'h133;
        gold_d[48] = 8'h94; gold_q[48] = 10'h18C;
        gold_d[49] = 8'hA0; gold_q[49] = 10'h39F;
        gold_d[50] = 8'h65; gold_q[50] = 10'h123;
        gold_d[51] = 8'h68; gold_q[51] = 10'h1D8;
        gold_d[52] = 8'h5D; gold_q[52] = 10'h061;
        gold_d[53] = 8'h64; gold_q[53] = 10'h1DC;
        gold_d[54] = 8'hC4; gold_q[54] = 10'h1BC;
        gold_d[55] = 8'h98; gold_q[55] = 10'h188;
        gold_d[56] = 8'h0B; gold_q[56] = 10'h1F9;
        gold_d[57] = 8'hB8; gold_q[57] = 10'h0C2;
        gold_d[58] = 8'hD4; gold_q[58] = 10'h0E6;
        gold_d[59] = 8'h54; gold_q[59] = 10'h1CC;
        gold_d[60] = 8'h4A; gold_q[60] = 10'h1C6;
        gold_d[61] = 8'h87; gold_q[61] = 10'h17D;
        gold_d[62] = 8'h21; gold_q[62] = 10'h3E0;
        gold_d[63] = 8'hA9; gold_q[63] = 10'h398;
    end
    initial begin
        repeat (3) @(posedge clk);
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            d = gold_d[i]; c = 2'b00; de = 1'b1;
            @(posedge clk);
            #1;
            checks = checks + 1;
            if (q !== gold_q[i]) begin errors = errors + 1; $display("FAIL golden %0d: d=%h got %h want %h", i, gold_d[i], q, gold_q[i]); end
        end
        @(negedge clk); de = 1'b0; c = 2'b00;
        repeat (2) @(posedge clk);
        // all 256 values, ascending and descending, then random runs, then constant runs (worst case for the balance)
        for (i = 0; i < 256; i = i + 1) step(i[7:0], 2'b00, 1'b1);
        for (i = 255; i >= 0; i = i - 1) step(i[7:0], 2'b00, 1'b1);
        for (i = 0; i < 20000; i = i + 1) step($random(seed), 2'b00, 1'b1);
        for (i = 0; i < 300; i = i + 1) step(8'hFF, 2'b00, 1'b1);
        for (i = 0; i < 300; i = i + 1) step(8'h01, 2'b00, 1'b1);
        for (i = 0; i < 300; i = i + 1) step(8'h0F, 2'b00, 1'b1);
        for (i = 0; i < 4; i = i + 1) step(8'h00, i[1:0], 1'b0);
        for (i = 0; i < 500; i = i + 1) begin
            step($random(seed), 2'b00, 1'b1);
            if (i % 7 == 0) step(8'h00, i[1:0], 1'b0);
        end
        checks = checks + 1;
        if (maxabs > 10) begin errors = errors + 1; $display("FAIL cumulative disparity reached %0d", maxabs); end
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d maxdisp=%0d PASS", checks, errors, maxabs);
        else $display("TBRESULT checks=%0d errors=%0d maxdisp=%0d FAIL", checks, errors, maxabs);
        $finish;
    end
    initial begin
        #50000000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
