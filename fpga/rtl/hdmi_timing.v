// SPDX-License-Identifier: MIT
// Video timing generator (pixel clock domain). Default: VESA DMT 1024x768@60 (65 MHz, both syncs negative): 1344 x 806 total.
// Contract: x/y are the current pixel coordinates (registered); de/hsync/vsync are combinational functions of x/y. After reset the counters start at
// x = 0 of the LAST line, so the first line request (line 0) is made before the first displayed line. `line_req` toggles at x == 2 of every line and
// `line_no` (stable from x == 1 to x == 1 of the next line) holds the number of the NEXT line to be fetched; no toggle is made when that line is outside
// the active area, so the fetcher sees exactly one request per displayed line.
module hdmi_timing #(
    parameter H_ACTIVE = 1024,
    parameter H_FRONT = 24,
    parameter H_SYNC = 136,
    parameter H_BACK = 160,
    parameter V_ACTIVE = 768,
    parameter V_FRONT = 3,
    parameter V_SYNC = 6,
    parameter V_BACK = 29,
    parameter HS_NEG = 1,
    parameter VS_NEG = 1
) (
    input  wire        pclk,
    input  wire        rst,
    output reg  [11:0] x,
    output reg  [11:0] y,
    output wire        de,
    output wire        hsync,
    output wire        vsync,
    output reg         line_req,
    output reg  [9:0]  line_no,
    output reg         frame_start  // one pclk pulse (registered) in the first cycle of line 0
);
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    wire [11:0] y_next = (y == V_TOTAL - 1) ? 12'd0 : y + 12'd1;

    assign de = (x < H_ACTIVE) && (y < V_ACTIVE);
    assign hsync = ((x >= H_ACTIVE + H_FRONT) && (x < H_ACTIVE + H_FRONT + H_SYNC)) ^ (HS_NEG != 0);
    assign vsync = ((y >= V_ACTIVE + V_FRONT) && (y < V_ACTIVE + V_FRONT + V_SYNC)) ^ (VS_NEG != 0);

    always @(posedge pclk) begin
        if (rst) begin
            x <= 12'd0;
            y <= V_TOTAL - 1;
            line_req <= 1'b0;
            line_no <= 10'd0;
            frame_start <= 1'b0;
        end else begin
            x <= (x == H_TOTAL - 1) ? 12'd0 : x + 12'd1;
            if (x == H_TOTAL - 1) y <= y_next;
            frame_start <= (x == H_TOTAL - 1) && (y == V_TOTAL - 1);
            if (x == 12'd1) line_no <= y_next[9:0];
            if (x == 12'd2 && y_next < V_ACTIVE) line_req <= ~line_req;
        end
    end
endmodule
