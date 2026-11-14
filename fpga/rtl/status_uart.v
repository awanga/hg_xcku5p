// SPDX-License-Identifier: MIT
// Periodically prints "C<c> P<pass> E<err> W<wr> R<rd> F<freq>\r\n" (hex, 54 bytes) on a UART.
// The values are sampled together at the start of each line, so one line is self-consistent.
// A line starts every INTERVAL clocks after reset; a line still being sent when the next interval
// ends is not interrupted (the next one starts when it finishes).
module status_uart #(
    parameter CLKS_PER_BIT = 1736,
    parameter INTERVAL = 67108864
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        calib,
    input  wire [31:0] pass,
    input  wire [31:0] err,
    input  wire [31:0] wr,
    input  wire [31:0] rd,
    input  wire [31:0] freq,
    output wire        tx
);
    reg [31:0] interval_cnt;
    reg        due;
    reg        calib_q;
    reg [31:0] pass_q, err_q, wr_q, rd_q, freq_q;
    reg [5:0]  idx;
    reg        sending;
    reg [7:0]  ch;
    wire       ready;
    wire       valid = sending;

    function [7:0] hex;
        input [3:0] n;
        begin
            hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
        end
    endfunction

    function [3:0] nib;
        input [31:0] v;
        input [2:0]  k; // 0 = most significant nibble
        begin
            nib = v[31 - 4 * k -: 4];
        end
    endfunction

    always @(*) begin
        case (idx)
        6'd0:  ch = "C";
        6'd1:  ch = hex({3'b000, calib_q});
        6'd2:  ch = " ";
        6'd3:  ch = "P";
        6'd12: ch = " ";
        6'd13: ch = "E";
        6'd22: ch = " ";
        6'd23: ch = "W";
        6'd32: ch = " ";
        6'd33: ch = "R";
        6'd42: ch = " ";
        6'd43: ch = "F";
        6'd52: ch = 8'h0D;
        6'd53: ch = 8'h0A;
        default: begin
            if (idx < 6'd12)
                ch = hex(nib(pass_q, idx[2:0] - 3'd4));
            else if (idx < 6'd22)
                ch = hex(nib(err_q, idx[2:0] - 3'd6));
            else if (idx < 6'd32)
                ch = hex(nib(wr_q, idx[2:0] - 3'd0));
            else if (idx < 6'd42)
                ch = hex(nib(rd_q, idx[2:0] - 3'd2));
            else
                ch = hex(nib(freq_q, idx[2:0] - 3'd4));
        end
        endcase
    end

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst_n(rst_n), .data(ch), .valid(valid), .ready(ready), .tx(tx));

    always @(posedge clk) begin
        if (!rst_n) begin
            interval_cnt <= 32'd0;
            due <= 1'b0;
            sending <= 1'b0;
            idx <= 6'd0;
            calib_q <= 1'b0;
            pass_q <= 32'd0;
            err_q <= 32'd0;
            wr_q <= 32'd0;
            rd_q <= 32'd0;
            freq_q <= 32'd0;
        end else begin
            if (interval_cnt == INTERVAL - 1) begin
                interval_cnt <= 32'd0;
                due <= 1'b1;
            end else
                interval_cnt <= interval_cnt + 1'b1;
            if (!sending) begin
                if (due) begin
                    due <= 1'b0;
                    sending <= 1'b1;
                    idx <= 6'd0;
                    calib_q <= calib;
                    pass_q <= pass;
                    err_q <= err;
                    wr_q <= wr;
                    rd_q <= rd;
                    freq_q <= freq;
                end
            end else if (valid && ready) begin
                if (idx == 6'd53)
                    sending <= 1'b0;
                else
                    idx <= idx + 1'b1;
            end
        end
    end
endmodule
