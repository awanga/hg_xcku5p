// SPDX-License-Identifier: MIT
// TMDS 8b/10b encoder for one DVI/HDMI channel (DVI 1.0 specification, section 3.3.1/3.3.3): transition-minimised 9-bit word, then DC balancing
// against the running disparity. Contract: q is registered, one pixel clock after d/c/de; when de is low the control code selected by c is sent
// and the running disparity returns to zero. Reset: disparity zero, q = control code 0.
module tmds_encoder (
    input  wire       clk,
    input  wire [7:0] d,
    input  wire [1:0] c,
    input  wire       de,
    output reg  [9:0] q = 10'b1101010100
);
    // number of ones in an 8-bit value
    function [3:0] ones8;
        input [7:0] v;
        integer i;
        begin
            ones8 = 4'd0;
            for (i = 0; i < 8; i = i + 1) ones8 = ones8 + {3'd0, v[i]};
        end
    endfunction

    reg signed [5:0] cnt = 6'sd0;  // running disparity: ones minus zeros sent so far, kept within +-8

    reg [8:0] qm;
    reg       use_xnor;
    reg [3:0] n1d, n1q;
    reg signed [5:0] diff;  // ones minus zeros in qm[7:0]
    reg [9:0] code;
    reg signed [5:0] cnt_next;
    integer i;

    always @* begin
        n1d = ones8(d);
        use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && d[0] == 1'b0);
        qm[0] = d[0];
        for (i = 1; i < 8; i = i + 1) qm[i] = use_xnor ? ~(qm[i-1] ^ d[i]) : (qm[i-1] ^ d[i]);
        qm[8] = ~use_xnor;
        n1q = ones8(qm[7:0]);
        diff = (2 * $signed({2'b00, n1q})) - 6'sd8;
        if (cnt == 6'sd0 || diff == 6'sd0) begin
            code[9] = ~qm[8];
            code[8] = qm[8];
            code[7:0] = qm[8] ? qm[7:0] : ~qm[7:0];
            cnt_next = qm[8] ? (cnt + diff) : (cnt - diff);
        end else if ((cnt > 6'sd0 && diff > 6'sd0) || (cnt < 6'sd0 && diff < 6'sd0)) begin
            code = {1'b1, qm[8], ~qm[7:0]};
            cnt_next = cnt + (qm[8] ? 6'sd2 : 6'sd0) - diff;
        end else begin
            code = {1'b0, qm[8], qm[7:0]};
            cnt_next = cnt - (qm[8] ? 6'sd0 : 6'sd2) + diff;
        end
    end

    always @(posedge clk) begin
        if (de) begin
            q <= code;
            cnt <= cnt_next;
        end else begin
            case (c)
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                default: q <= 10'b1010101011;
            endcase
            cnt <= 6'sd0;
        end
    end
endmodule
