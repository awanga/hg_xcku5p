// SPDX-License-Identifier: MIT
// Periodic single-register read through a DRP port (SYSMONE4 temperature, address 0).
// Contract: every 2^PERIOD_BITS clk cycles den is high for one cycle with daddr = ADDR and dwe low; the register read is the do value
// seen while drdy is high, held in value until the next read completes. A read that has not completed when the next period starts is
// not repeated (den is only issued from the idle state), so a stalled port cannot be flooded. value is 0 until the first read
// completes; software treats 0 as "no reading".
module drp_reader #(
    parameter [6:0] ADDR = 7'h00,
    parameter PERIOD_BITS = 16
) (
    input  wire        clk,
    input  wire        rst_n,
    output reg         den,
    output wire [6:0]  daddr,
    input  wire        drdy,
    input  wire [15:0] do_in,
    output reg  [15:0] value
);
    reg [PERIOD_BITS-1:0] cnt;
    reg busy;
    assign daddr = ADDR;

    always @(posedge clk) begin
        den <= 1'b0;
        if (!rst_n) begin
            cnt <= {PERIOD_BITS{1'b0}};
            busy <= 1'b0;
            value <= 16'd0;
        end else begin
            cnt <= cnt + 1'b1;
            if (busy) begin
                if (drdy) begin
                    value <= do_in;
                    busy <= 1'b0;
                end
            end else if (&cnt) begin
                den <= 1'b1;
                busy <= 1'b1;
            end
        end
    end
endmodule
