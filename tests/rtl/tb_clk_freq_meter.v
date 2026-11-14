// SPDX-License-Identifier: MIT
// Expected counts come from the definition count = f_meas * 2^15 / f_ref (+-2 for the gate edges crossing clock domains).
`timescale 1ns / 1ps
module tb_clk_freq_meter;
    reg ref_clk = 1'b0;
    always #5 ref_clk = ~ref_clk;           // 100 MHz
    reg meas_clk = 1'b0;
    integer half = 4;                        // 125 MHz; 0 stops the clock
    always begin
        if (half == 0) #10 meas_clk = 1'b0;
        else begin #(half) meas_clk = ~meas_clk; end
    end
    wire [31:0] count;
    clk_freq_meter dut (.ref_clk(ref_clk), .meas_clk(meas_clk), .count(count));
    integer errors = 0, checks = 0;
    task check_near(input integer got, input integer want, input [255:0] what);
        begin
            checks = checks + 1;
            if (got < want - 2 || got > want + 2) begin errors = errors + 1; $display("FAIL %0s: got %0d want %0d", what, got, want); end
        end
    endtask
    localparam FRAME = 131072 * 10;          // one full four-phase cycle in ns
    initial begin
        #(FRAME * 2 + 100);
        check_near(count, 40960, "125 MHz");
        half = 20;                           // 25 MHz
        #(FRAME * 2 + 100);
        check_near(count, 8192, "25 MHz");
        half = 200;                          // 2.5 MHz
        #(FRAME * 2 + 100);
        check_near(count, 819, "2.5 MHz");
        half = 0;                            // PHY clock absent
        #(FRAME * 2 + 100);
        check_near(count, 0, "no clock");
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
