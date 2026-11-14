// SPDX-License-Identifier: MIT
// Expected from the contract in drp_reader.v, with a behavioural DRP slave (latency 3 cycles, content changes between reads):
// - den is a one-cycle pulse once per 2^PERIOD_BITS cycles and always carries daddr = ADDR;
// - value is 0 before the first read, then equals the slave's register as it was when the read was served, and holds in between;
// - a slave that never answers gets exactly one den (no flooding).
`timescale 1ns / 1ps
module tb_drp_reader;
    parameter PB = 5;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    wire den, drdy_ok;
    wire [6:0] daddr;
    wire [15:0] value;
    reg [15:0] reg_content = 16'hA001;
    reg [2:0] lat = 3'd0;
    reg drdy = 1'b0;
    reg [15:0] dout = 16'd0;
    reg mute = 1'b0;
    integer dens = 0, errors = 0, checks = 0, i;
    drp_reader #(.ADDR(7'h00), .PERIOD_BITS(PB)) dut (.clk(clk), .rst_n(rst_n), .den(den), .daddr(daddr), .drdy(drdy), .do_in(dout), .value(value));
    // slave
    always @(posedge clk) begin
        drdy <= 1'b0;
        if (den && !mute) lat <= 3'd3;
        else if (lat != 3'd0) begin
            lat <= lat - 1'b1;
            if (lat == 3'd1) begin drdy <= 1'b1; dout <= reg_content; end
        end
        if (den) begin
            dens = dens + 1;
            checks = checks + 1;
            if (daddr !== 7'h00) begin errors = errors + 1; $display("FAIL: daddr %h", daddr); end
        end
    end
    task chk(input [15:0] got, input [15:0] want, input [127:0] what);
        begin checks = checks + 1; if (got !== want) begin errors = errors + 1; $display("FAIL: %0s got %h want %h", what, got, want); end end
    endtask
    initial begin
        repeat (4) @(posedge clk);
        chk(value, 16'd0, "value after reset");
        // first den: 2^PB clock edges after reset release (the counter must run through its whole range first)
        @(negedge clk);
        rst_n = 1'b1;
        i = 0;
        while (!den && i < 200) begin @(negedge clk); i = i + 1; end
        chk(i, (1 << PB), "edges from reset release to the first den");
        repeat (40) @(posedge clk);
        chk(value, 16'hA001, "first read");
        reg_content = 16'hB234;
        chk(value, 16'hA001, "value holds between reads");
        repeat (40) @(posedge clk);
        chk(value, 16'hB234, "second read");
        // exactly one den per period: 3 periods -> 3 pulses
        dens = 0;
        repeat (3 * (1 << PB)) @(posedge clk);
        chk(dens, 16'd3, "den count over three periods");
        // slave that never answers: one den, then nothing
        mute = 1'b1;
        @(posedge clk);
        dens = 0;
        repeat (6 * (1 << PB)) @(posedge clk);
        chk(dens, 16'd1, "den count with a mute slave");
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
