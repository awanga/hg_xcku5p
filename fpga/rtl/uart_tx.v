// SPDX-License-Identifier: MIT
// 8N1 UART transmitter. Contract: byte is accepted in the cycle valid && ready; ready is low while a
// frame (start, 8 data bits LSB first, stop) is on the line. tx idles high, including in reset.
module uart_tx #(
    parameter CLKS_PER_BIT = 1736
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,
    output wire       ready,
    output reg        tx
);
    reg [3:0]  nbits;
    reg [10:0] cnt;
    reg [8:0]  shreg;

    assign ready = (nbits == 4'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            tx <= 1'b1;
            nbits <= 4'd0;
            cnt <= 11'd0;
            shreg <= 9'h1FF;
        end else if (ready) begin
            if (valid) begin
                tx <= 1'b0;
                shreg <= {1'b1, data};
                nbits <= 4'd10;
                cnt <= CLKS_PER_BIT - 1;
            end
        end else if (cnt == 11'd0) begin
            cnt <= CLKS_PER_BIT - 1;
            nbits <= nbits - 1'b1;
            tx <= shreg[0];
            shreg <= {1'b1, shreg[8:1]};
        end else begin
            cnt <= cnt - 1'b1;
        end
    end
endmodule
