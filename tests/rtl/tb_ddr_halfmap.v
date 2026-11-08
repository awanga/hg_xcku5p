// SPDX-License-Identifier: MIT
// Expected from the contract in ddr_halfmap.v: bits [29:0] pass through; bit 30 = sel only for addr[29:28] == 2'b11.
`timescale 1ns / 1ps
module tb_ddr_halfmap;
    reg  [29:0] addr = 30'd0;
    reg         sel = 1'b0;
    wire [30:0] o;
    ddr_halfmap dut (.addr(addr), .sel(sel), .ddr_addr(o));
    integer errors = 0, checks = 0, i, s;
    reg [30:0] want;
    reg [29:0] a;
    initial begin
        for (s = 0; s < 2; s = s + 1) begin
            sel = s[0];
            for (i = 0; i < 400; i = i + 1) begin
                // sweeps all four quarters at their edges plus a pseudo-random mix
                case (i % 8)
                0: a = 30'h0;
                1: a = 30'h0FFFFFFF;
                2: a = 30'h10000000;
                3: a = 30'h1FFFFFFF;
                4: a = 30'h20000000;
                5: a = 30'h2FFFFFFF;
                6: a = 30'h30000000;
                default: a = (i * 30'd2654435) ^ (i << 20);
                endcase
                if (i == 7) a = 30'h3FFFFFFF;
                addr = a;
                #1;
                want = {(s == 1) && (a[29:28] == 2'b11), a};
                checks = checks + 1;
                if (o !== want) begin errors = errors + 1; $display("FAIL sel=%0d addr=%h got %h want %h", s, a, o, want); end
            end
        end
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
