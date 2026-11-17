// SPDX-License-Identifier: MIT
// 8N1 UART receiver. Contract: `valid` is a one-cycle pulse with `data` when a frame with a high stop bit ends (sampled mid stop bit); a frame with a low
// stop bit is dropped and pulses `ferr` instead. A start bit is a falling edge that is still low at the middle of the bit (shorter glitches are ignored).
// The input is double-registered. rx idles high.
module uart_rx #(
    parameter CLKS_PER_BIT = 1447
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        ferr
);
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rs;
    reg [1:0]  st;
    reg [2:0]  bitn;
    reg [11:0] cnt;
    reg [7:0]  sh;

    always @(posedge clk) begin
        rs <= {rs[0], rx};
        valid <= 1'b0;
        ferr <= 1'b0;
        if (!rst_n) begin
            rs <= 2'b11;
            st <= S_IDLE;
            cnt <= 12'd0;
            bitn <= 3'd0;
        end else begin
            case (st)
            S_IDLE: if (!rs[1]) begin
                st <= S_START;
                cnt <= CLKS_PER_BIT / 2 - 1;
            end
            S_START: if (cnt != 12'd0) cnt <= cnt - 1'b1;
                else if (rs[1]) st <= S_IDLE;
                else begin
                    st <= S_DATA;
                    cnt <= CLKS_PER_BIT - 1;
                    bitn <= 3'd0;
                end
            S_DATA: if (cnt != 12'd0) cnt <= cnt - 1'b1;
                else begin
                    sh <= {rs[1], sh[7:1]};
                    cnt <= CLKS_PER_BIT - 1;
                    bitn <= bitn + 1'b1;
                    if (bitn == 3'd7) st <= S_STOP;
                end
            S_STOP: if (cnt != 12'd0) cnt <= cnt - 1'b1;
                else begin
                    st <= S_IDLE;
                    data <= sh;
                    valid <= rs[1];
                    ferr <= !rs[1];
                end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
