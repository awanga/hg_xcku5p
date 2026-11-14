// SPDX-License-Identifier: MIT
// Address-dependent write/read-back memory test, AXI4 master, 256-bit data.
//
// Contract:
//  - One burst outstanding at a time. A burst is 16 beats x 32 B = 512 B, INCR, ID 0.
//  - Nothing is issued until enable is seen high in ST_IDLE; after that enable is ignored.
//  - rlast must be set exactly on beat 15 of a burst; a mismatch counts as an error.
//  - Each pass writes bursts 0..NBURSTS-1, then reads them back and compares. Pass N uses
//    key = N*32'h9E3779B9 + 32'hA5A5A5A5; word w of beat b is xorshift32((8*b+w+1) ^ key), b the
//    global beat index (16*burst+beat). Data therefore depends on address and on the pass.
//  - err_cnt counts mismatching beats plus non-OKAY write/read responses, saturating.
//  - timeout latches and the FSM stops if no AXI handshake happens for 2^TIMEOUT_BITS cycles.
//  - All counters are held after reset to 0. wr_cycles/rd_cycles are the cycle counts of the most
//    recent completed write/read phase (clock cycles of clk, including AXI stalls).
module axi_memtest #(
    parameter NBURSTS = 131072,
    parameter TIMEOUT_BITS = 24
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,

    output reg  [29:0]  awaddr,
    output reg          awvalid,
    input  wire         awready,
    output wire [255:0] wdata,
    output wire         wlast,
    output reg          wvalid,
    input  wire         wready,
    input  wire [1:0]   bresp,
    input  wire         bvalid,
    output wire         bready,
    output reg  [29:0]  araddr,
    output reg          arvalid,
    input  wire         arready,
    input  wire [255:0] rdata,
    input  wire [1:0]   rresp,
    input  wire         rlast,
    input  wire         rvalid,
    output wire         rready,

    output reg  [31:0]  pass_cnt,
    output reg  [31:0]  err_cnt,
    output reg  [31:0]  wr_cycles,
    output reg  [31:0]  rd_cycles,
    output reg  [29:0]  first_err_addr,
    output reg          timeout,
    output wire         busy
);
    localparam ST_IDLE = 2'd0;
    localparam ST_WR   = 2'd1;
    localparam ST_RD   = 2'd2;
    localparam ST_HALT = 2'd3;

    function [31:0] mix;
        input [31:0] seed;
        reg [31:0] x;
        begin
            x = seed;
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            mix = x;
        end
    endfunction

    function [255:0] pattern;
        input [31:0] beat;
        input [31:0] key;
        integer w;
        reg [255:0] v;
        begin
            v = 256'd0;
            for (w = 0; w < 8; w = w + 1)
                v[32*w +: 32] = mix(((beat << 3) + w + 1) ^ key);
            pattern = v;
        end
    endfunction

    reg [1:0]  state;
    reg [20:0] burst;
    reg [3:0]  beat;
    reg [31:0] key;
    reg        err_seen;
    reg [31:0] phase_cnt;
    reg [TIMEOUT_BITS-1:0] wd;

    wire [31:0] gbeat_w = {7'd0, burst, beat};
    wire [31:0] gbeat_r = {7'd0, burst, beat};
    wire last_burst = (burst == NBURSTS - 1);
    wire w_hs = wvalid && wready;
    wire b_hs = bvalid && bready;
    wire r_hs = rvalid && rready;
    wire aw_hs = awvalid && awready;
    wire ar_hs = arvalid && arready;
    wire r_bad = (rdata != pattern(gbeat_r, key)) || (rresp != 2'b00) || (rlast != wlast);
    wire err_sat = (err_cnt == 32'hFFFFFFFF);

    assign wdata = pattern(gbeat_w, key);
    assign wlast = (beat == 4'd15);
    assign bready = (state == ST_WR);
    assign rready = (state == ST_RD);
    assign busy = (state == ST_WR) || (state == ST_RD);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            burst <= 21'd0;
            beat <= 4'd0;
            key <= 32'hA5A5A5A5;
            awvalid <= 1'b0;
            wvalid <= 1'b0;
            arvalid <= 1'b0;
            awaddr <= 30'd0;
            araddr <= 30'd0;
            err_seen <= 1'b0;
            phase_cnt <= 32'd0;
            wd <= {TIMEOUT_BITS{1'b0}};
            pass_cnt <= 32'd0;
            err_cnt <= 32'd0;
            wr_cycles <= 32'd0;
            rd_cycles <= 32'd0;
            first_err_addr <= 30'd0;
            timeout <= 1'b0;
        end else begin
            if (aw_hs || w_hs || b_hs || ar_hs || r_hs)
                wd <= {TIMEOUT_BITS{1'b0}};
            else if (busy)
                wd <= wd + 1'b1;
            if (busy && &wd) begin
                timeout <= 1'b1;
                state <= ST_HALT;
                awvalid <= 1'b0;
                wvalid <= 1'b0;
                arvalid <= 1'b0;
            end else begin
                case (state)
                ST_IDLE: begin
                    if (enable) begin
                        state <= ST_WR;
                        burst <= 21'd0;
                        beat <= 4'd0;
                        awaddr <= 30'd0;
                        awvalid <= 1'b1;
                        wvalid <= 1'b1;
                        phase_cnt <= 32'd1;
                    end
                end
                ST_WR: begin
                    phase_cnt <= phase_cnt + 1'b1;
                    if (aw_hs)
                        awvalid <= 1'b0;
                    if (w_hs) begin
                        if (wlast) begin
                            wvalid <= 1'b0;
                        end
                        beat <= beat + 1'b1;
                    end
                    if (b_hs) begin
                        if (bresp != 2'b00 && !err_sat)
                            err_cnt <= err_cnt + 1'b1;
                        if (last_burst) begin
                            wr_cycles <= phase_cnt;
                            state <= ST_RD;
                            burst <= 21'd0;
                            beat <= 4'd0;
                            araddr <= 30'd0;
                            arvalid <= 1'b1;
                            phase_cnt <= 32'd1;
                        end else begin
                            burst <= burst + 1'b1;
                            awaddr <= awaddr + 30'd512;
                            awvalid <= 1'b1;
                            wvalid <= 1'b1;
                        end
                    end
                end
                ST_RD: begin
                    phase_cnt <= phase_cnt + 1'b1;
                    if (ar_hs)
                        arvalid <= 1'b0;
                    if (r_hs) begin
                        if (r_bad) begin
                            if (!err_sat)
                                err_cnt <= err_cnt + 1'b1;
                            if (!err_seen) begin
                                err_seen <= 1'b1;
                                first_err_addr <= {burst, beat, 5'd0};
                            end
                        end
                        beat <= rlast ? 4'd0 : beat + 1'b1;
                        if (rlast) begin
                            if (last_burst) begin
                                rd_cycles <= phase_cnt;
                                pass_cnt <= pass_cnt + 1'b1;
                                key <= key + 32'h9E3779B9;
                                state <= ST_WR;
                                burst <= 21'd0;
                                awaddr <= 30'd0;
                                awvalid <= 1'b1;
                                wvalid <= 1'b1;
                                phase_cnt <= 32'd1;
                            end else begin
                                burst <= burst + 1'b1;
                                araddr <= araddr + 30'd512;
                                arvalid <= 1'b1;
                            end
                        end
                    end
                end
                default: ;
                endcase
            end
        end
    end
endmodule
