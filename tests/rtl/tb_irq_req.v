// SPDX-License-Identifier: MIT
// Testbench for irq_req: expected behaviour is written from the contract in the module header.
`timescale 1ns/1ps
module tb_irq_req;
    reg clk = 0, rst_n = 0, lvl = 0, ack = 0;
    wire req, seen;
    always #4 clk = ~clk;
    integer checks = 0, errors = 0;
    irq_req d (.clk(clk), .rst_n(rst_n), .lvl(lvl), .ack(ack), .req(req), .seen(seen));
    task chk(input got, input exp, input [255:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin errors = errors + 1; $display("MISMATCH %0s: got %b expected %b", what, got, exp); end
        end
    endtask
    task cyc(input integer n); begin repeat (n) @(negedge clk); end endtask
    initial begin
        cyc(3); rst_n = 1; cyc(3);
        chk(req, 0, "idle"); chk(seen, 0, "seen idle");
        lvl = 1; cyc(1); chk(req, 0, "not before the synchroniser"); cyc(3); chk(seen, 1, "seen follows the level");
        chk(req, 1, "request after the level rises");
        cyc(10); chk(req, 1, "request held without ack");
        ack = 1; cyc(1); ack = 0; cyc(2);
        chk(req, 0, "request drops after ack");
        cyc(10); chk(req, 0, "no second request while the level stays high");
        lvl = 0; cyc(4); chk(req, 0, "still idle after the level falls");
        lvl = 1; cyc(5); chk(req, 1, "new request after the level rose again");
        lvl = 0; cyc(5); chk(req, 0, "request dropped when the level falls before the ack");
        lvl = 1; cyc(5); chk(req, 1, "request again");
        ack = 1; cyc(1); ack = 0; cyc(3); chk(req, 0, "acked");
        rst_n = 0; cyc(2); chk(seen, 1, "seen is valid in reset"); chk(req, 0, "no request in reset"); rst_n = 1; cyc(5);
        chk(req, 1, "after reset a still-high level requests again");
        lvl = 0; cyc(4); chk(req, 0, "cleared");
        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (checks > 0 && errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin #20000; $display("TBRESULT watchdog FAIL"); $finish; end
endmodule
