// SPDX-License-Identifier: MIT
// Turns a level interrupt into a short pulse on each rising edge. The SPI driver disables its interrupt from the handler, but that
// register write reaches the peripheral clock domain only after crossing the AXI clock converter; the PLIC would re-arm
// at "complete" while the level is still high and call the handler again, and the second complete() can wake a later transfer early.
// The pulse is HOLD cycles long so the faster CPU clock samples it reliably.
module irq_pulse #(
    parameter HOLD = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire level,
    output wire pulse
);
    reg       level_q;
    reg [2:0] cnt;
    assign pulse = (cnt != 3'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            level_q <= 1'b0;
            cnt <= 3'd0;
        end else begin
            level_q <= level;
            if (level && !level_q) cnt <= HOLD[2:0];
            else if (cnt != 3'd0) cnt <= cnt - 3'd1;
        end
    end
endmodule
