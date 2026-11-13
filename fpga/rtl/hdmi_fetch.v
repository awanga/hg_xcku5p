// SPDX-License-Identifier: MIT
// Line fetcher for the HDMI scan-out (AXI clock domain). One request per displayed line arrives as a toggle from the pixel clock domain; the line
// (LINE_BEATS 64-bit beats, RGB565 pixels) is read with BURST-beat INCR bursts from fb_base + line * LINE_BYTES into one half of the line buffer
// (half = line[0], so the scan-out reads the other half meanwhile). Contract:
//   - fb_base is latched when line 0 is requested (a base change takes effect at the next frame); it must be LINE_BYTES aligned.
//   - A request that arrives while a line is still being fetched is counted in `late` and dropped; a non-OKAY read response sets `rerr` (sticky).
//   - While `en` is low requests are ignored. `line_no` is sampled two clocks after the toggle (the pixel side holds it stable).
//   - `lines` counts completed lines.
module hdmi_fetch #(
    parameter LINE_BEATS = 256,  // 1024 pixels * 2 bytes / 8
    parameter BURST = 16         // beats per AXI burst (INCR); LINE_BEATS must be a multiple, 64-bit beats
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [31:0] fb_base,
    input  wire        req,       // toggle from the pixel domain
    input  wire [9:0]  line_no,   // from the pixel domain, stable around the toggle
    input  wire        clr,       // pulse: clear late/rerr/lines
    // AXI4 read master
    output reg  [31:0] araddr,
    output wire [7:0]  arlen,
    output reg         arvalid,
    input  wire        arready,
    input  wire [63:0] rdata,
    input  wire [1:0]  rresp,
    input  wire        rvalid,
    output wire        rready,
    // line buffer write port
    output wire        ram_we,
    output wire [8:0]  ram_waddr,
    output wire [63:0] ram_wdata,
    output reg  [31:0] late,
    output reg  [31:0] lines,
    output reg         rerr,
    output reg         busy
);
    localparam NBURST = LINE_BEATS / BURST;
    localparam LINE_BYTES = LINE_BEATS * 8;

    (* ASYNC_REG = "TRUE" *) reg [2:0] rq = 3'd0;
    wire      new_req = rq[1] ^ rq[2];
    reg [31:0] base_q;
    reg        bank;
    reg [5:0]  ar_cnt;
    reg [8:0]  r_cnt;

    assign arlen = BURST - 1;
    assign rready = busy;
    assign ram_we = busy && rvalid;
    assign ram_waddr = {bank, r_cnt[7:0]};
    assign ram_wdata = rdata;

    always @(posedge clk) begin
        rq <= {rq[1:0], req};
        if (!rst_n) begin
            busy <= 1'b0;
            arvalid <= 1'b0;
            late <= 32'd0;
            lines <= 32'd0;
            rerr <= 1'b0;
        end else begin
            if (clr) begin
                late <= 32'd0;
                lines <= 32'd0;
                rerr <= 1'b0;
            end
            if (new_req && en) begin
                if (busy) begin
                    late <= late + 32'd1;
                end else begin
                    busy <= 1'b1;
                    bank <= line_no[0];
                    ar_cnt <= 6'd0;
                    r_cnt <= 9'd0;
                    arvalid <= 1'b1;
                    if (line_no == 10'd0) begin
                        base_q <= fb_base;
                        araddr <= fb_base;
                    end else begin
                        araddr <= base_q + line_no * LINE_BYTES;
                    end
                end
            end
            if (busy && arvalid && arready) begin
                ar_cnt <= ar_cnt + 6'd1;
                araddr <= araddr + BURST * 8;
                if (ar_cnt == NBURST - 1) arvalid <= 1'b0;
            end
            if (busy && rvalid) begin
                if (rresp != 2'b00) rerr <= 1'b1;
                r_cnt <= r_cnt + 9'd1;
                if (r_cnt == LINE_BEATS - 1) begin
                    busy <= 1'b0;
                    lines <= lines + 32'd1;
                end
            end
        end
    end
endmodule
