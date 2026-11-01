// SPDX-License-Identifier: MIT
// Counts edges of meas_clk during a gate of 2^15 ref_clk cycles and holds the result until the next measurement:
// count = f_meas * 2^15 / f_ref (ref 100 MHz: 125 MHz -> 40960, 25 MHz -> 8192, 2.5 MHz -> 819, stopped -> 0).
// Four phases of 2^15 ref cycles: idle, count, settle, sample. The counter free-runs only while the gate is high and is read only
// while the gate is low, so it never changes during the transfer into the ref domain; the result is the difference of two such
// reads, which is 0 for a stopped clock.
module clk_freq_meter (
    input  wire        ref_clk,
    input  wire        meas_clk,
    output reg  [31:0] count
);
    reg [14:0] ph_cnt = 15'd0;
    reg [1:0]  ph = 2'd0;
    always @(posedge ref_clk) begin
        ph_cnt <= ph_cnt + 1'b1;
        if (ph_cnt == 15'h7FFF) ph <= ph + 1'b1;
    end
    wire gate = (ph == 2'd1);

    (* ASYNC_REG = "TRUE" *) reg [1:0] gate_s = 2'b00;
    reg [31:0] cnt = 32'd0;
    always @(posedge meas_clk) begin
        gate_s <= {gate_s[0], gate};
        if (gate_s[1]) cnt <= cnt + 1'b1;
    end

    reg [31:0] snap0 = 32'd0;
    always @(posedge ref_clk) begin
        if (ph == 2'd0 && ph_cnt == 15'h7FFF) snap0 <= cnt;
        if (ph == 2'd3 && ph_cnt == 15'd0) count <= cnt - snap0;
    end
    initial count = 32'd0;
endmodule
