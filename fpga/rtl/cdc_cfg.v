// SPDX-License-Identifier: MIT
// Quasi-static configuration bus across clock domains (toggle request / toggle acknowledge). The source value is copied into a holding register
// that stays unchanged until the destination has taken it, so the destination never samples a word while it changes. A new source value that
// arrives while a transfer is in flight is picked up right after it (intermediate values may be skipped, the last one always arrives).
// Latency: a few cycles of each clock. `q` is zero while dst_rst_n is low.
module cdc_cfg #(
    parameter W = 32
) (
    input  wire         src_clk,
    input  wire         src_rst_n,
    input  wire [W-1:0] d,
    input  wire         dst_clk,
    input  wire         dst_rst_n,
    output reg  [W-1:0] q
);
    reg [W-1:0] hold;
    reg         req, busy;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_s;
    reg         ack;    // destination domain
    always @(posedge src_clk) begin
        ack_s <= {ack_s[0], ack};
        if (!src_rst_n) begin
            hold <= {W{1'b0}};
            req <= 1'b0;
            busy <= 1'b0;
        end else if (busy) begin
            if (ack_s[1] == req) busy <= 1'b0;
        end else if (d != hold) begin
            hold <= d;
            req <= ~req;
            busy <= 1'b1;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] req_s;
    always @(posedge dst_clk) begin
        req_s <= {req_s[0], req};
        if (!dst_rst_n) begin
            q <= {W{1'b0}};
            ack <= 1'b0;
            req_s <= 2'b00;
        end else if (req_s[1] != ack) begin
            q <= hold;
            ack <= req_s[1];
        end
    end
endmodule
