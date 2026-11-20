// SPDX-License-Identifier: MIT
// Self-test master for one user DDR4 port of the CPU-less PCIe card (user_ip): writes a counted pattern to DDR4, reads it back, compares, and counts cycles.
// A template for how a block drives a port: AXI4, 256-bit data, 32-bit address, INCR bursts of at most 16 beats, one burst in flight, clock `mclk`
// (the DDR4 user clock, 333 MHz at tCK 750 ps). Its registers are on `clk` (the register clock); the few signals that cross are listed below.
// Registers (word index in `raddr`/`waddr`):
//   0 CTRL      WO  bit0: start a run (ignored while busy; user_ip START starts several ports in the same clock); bit1: clear DONE, ERR and the counters
//   1 STATUS    RO  bit0 BUSY, bit1 DONE (set at the end of a run, cleared by start or clear), bit2 ERR (a response other than OKAY was seen)
//   2 BASE      RW  byte address of the first beat; bits 8:0 read 0 (512-byte aligned, so no burst crosses a 4 KiB boundary)
//   3 BEATS     RW  number of 256-bit beats, 1 .. 2^20-1 (0 is taken as 1)
//   4 SEED      RW  beat k, lane j (32 bits, lane 0 = bits 31:0) = SEED + 8*k + j (mod 2^32)
//   5 MISMATCH  RO  number of read beats that differ from the pattern (saturates at 2^32-1)
//   6 WR_CYCLES RO  `mclk` cycles from the start to the last write response
//   7 RD_CYCLES RO  `mclk` cycles from the first read address to the last read beat
// Crossing: BASE, BEATS and SEED (register clock) are sampled by the engine two or more `mclk` cycles after the start request has crossed, and must not
// change while BUSY; the read-only results (MISMATCH, WR_CYCLES, RD_CYCLES, ERR) are read after DONE has been seen and do not change then. Constraints:
// fpga/constraints/card_board.xdc (names cfg_*, res_*).
module mem_probe (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [2:0]   waddr,
    input  wire         we,
    input  wire [31:0]  wdata,
    input  wire         go_ext,     // start request from a pulse (user_ip START), same as CTRL bit 0
    input  wire [2:0]   raddr,
    output reg  [31:0]  rdata,
    input  wire         mclk,
    input  wire         mrst_n,
    output reg  [31:0]  m_awaddr,
    output reg  [7:0]   m_awlen,
    output wire [2:0]   m_awsize,
    output wire [1:0]   m_awburst,
    output wire [3:0]   m_awid,
    output reg          m_awvalid,
    input  wire         m_awready,
    output reg  [255:0] m_wdata,
    output wire [31:0]  m_wstrb,
    output reg          m_wlast,
    output reg          m_wvalid,
    input  wire         m_wready,
    input  wire [3:0]   m_bid,
    input  wire [1:0]   m_bresp,
    input  wire         m_bvalid,
    output reg          m_bready,
    output reg  [31:0]  m_araddr,
    output reg  [7:0]   m_arlen,
    output wire [2:0]   m_arsize,
    output wire [1:0]   m_arburst,
    output wire [3:0]   m_arid,
    output reg          m_arvalid,
    input  wire         m_arready,
    input  wire [3:0]   m_rid,
    input  wire [255:0] m_rdata,
    input  wire [1:0]   m_rresp,
    input  wire         m_rlast,
    input  wire         m_rvalid,
    output reg          m_rready
);
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_ids = &{1'b0, m_bid, m_rid, m_rlast};
    /* verilator lint_on UNUSEDSIGNAL */
    assign m_awsize = 3'd5;
    assign m_arsize = 3'd5;
    assign m_awburst = 2'b01;
    assign m_arburst = 2'b01;
    assign m_awid = 4'd0;
    assign m_arid = 4'd0;
    assign m_wstrb = 32'hFFFFFFFF;

    // ------------------------------------------------------------ register side (clk)
    reg [31:0] cfg_base, cfg_seed;
    reg [19:0] cfg_beats;
    reg        go_t, clr_t;          // toggles: a request is one change
    (* ASYNC_REG = "TRUE" *) reg [1:0] busy_s, done_s, err_s;
    reg        res_busy, res_done, res_err;
    reg [31:0] res_mism, res_wr, res_rd;

    always @(posedge clk) begin
        busy_s <= {busy_s[0], res_busy};
        done_s <= {done_s[0], res_done};
        err_s <= {err_s[0], res_err};
        if (!rst_n) begin
            cfg_base <= 32'd0;
            cfg_seed <= 32'd0;
            cfg_beats <= 20'd1;
            go_t <= 1'b0;
            clr_t <= 1'b0;
        end else begin
            if (go_ext && !busy_s[1]) go_t <= ~go_t;
            if (we) case (waddr)
            3'd0: begin
                if (wdata[0] && !busy_s[1] && !go_ext) go_t <= ~go_t;
                if (wdata[1]) clr_t <= ~clr_t;
            end
            3'd2: cfg_base <= {wdata[31:9], 9'd0};
            3'd3: cfg_beats <= (wdata[19:0] == 20'd0) ? 20'd1 : wdata[19:0];
            3'd4: cfg_seed <= wdata;
            default: ;
            endcase
        end
    end
    always @(*) begin
        case (raddr)
        3'd1: rdata = {29'd0, err_s[1], done_s[1], busy_s[1]};
        3'd2: rdata = cfg_base;
        3'd3: rdata = {12'd0, cfg_beats};
        3'd4: rdata = cfg_seed;
        3'd5: rdata = res_mism;
        3'd6: rdata = res_wr;
        3'd7: rdata = res_rd;
        default: rdata = 32'd0;
        endcase
    end

    // ------------------------------------------------------------ engine (mclk)
    // Timing (333 MHz): no adder chain feeds a comparator. The write data of the next beat and the expected data of the beat being read are each one
    // 32-bit add of a registered base and a constant, registered; the compare works on registered data and its result is counted one stage later.
    (* ASYNC_REG = "TRUE" *) reg [1:0] go_s, clr_s;
    reg go_q, clr_q;
    reg [31:0] e_seed, wbase, ebase;
    reg [19:0] w_left, r_left;
    reg [4:0]  burst_beat;
    reg [3:0]  st;
    reg [1:0]  flush;
    reg [255:0] rd_q, exp_q;
    reg         rd_v, mism_c;
    localparam IDLE = 4'd0, WAW = 4'd1, WDATA = 4'd2, WRSP = 4'd3, RAR = 4'd4, RDATA = 4'd5, FLUSH = 4'd6, FIN = 4'd7;

    // lanes of a beat whose first lane is `b`: lane j = b + j
    function [255:0] lanes(input [31:0] b);
        integer j;
        begin
            for (j = 0; j < 8; j = j + 1) lanes[32*j +: 32] = b + j;
        end
    endfunction
    // lanes of the beat after the one whose first lane is `b`: lane j = b + 8 + j (one add of a constant per lane)
    function [255:0] lanes_next(input [31:0] b);
        integer j;
        begin
            for (j = 0; j < 8; j = j + 1) lanes_next[32*j +: 32] = b + 8 + j;
        end
    endfunction

    wire go_edge = go_s[1] ^ go_q;
    wire clr_edge = clr_s[1] ^ clr_q;
    wire [19:0] left_now = (st == WAW || st == WDATA) ? w_left : r_left;
    wire [7:0]  burst_len = (left_now > 20'd16) ? 8'd15 : (left_now[7:0] - 8'd1);

    always @(posedge mclk) begin
        go_s <= {go_s[0], go_t};
        clr_s <= {clr_s[0], clr_t};
        go_q <= go_s[1];
        clr_q <= clr_s[1];
        // read check pipeline: capture, compare, count
        exp_q <= lanes(ebase);
        rd_v <= m_rvalid && m_rready;
        rd_q <= m_rdata;
        mism_c <= rd_v && (rd_q != exp_q);
        if (!mrst_n) begin
            st <= IDLE;
            res_busy <= 1'b0;
            res_done <= 1'b0;
            res_err <= 1'b0;
            res_mism <= 32'd0;
            res_wr <= 32'd0;
            res_rd <= 32'd0;
            m_awvalid <= 1'b0;
            m_wvalid <= 1'b0;
            m_wlast <= 1'b0;
            m_bready <= 1'b0;
            m_arvalid <= 1'b0;
            m_rready <= 1'b0;
            rd_v <= 1'b0;
            mism_c <= 1'b0;
        end else begin
            if (clr_edge && st == IDLE) begin
                res_done <= 1'b0;
                res_err <= 1'b0;
                res_mism <= 32'd0;
                res_wr <= 32'd0;
                res_rd <= 32'd0;
            end
            if (mism_c && res_mism != 32'hFFFFFFFF) res_mism <= res_mism + 32'd1;
            if (res_busy && (st == WAW || st == WDATA || st == WRSP)) res_wr <= res_wr + 32'd1;
            if (res_busy && (st == RAR || st == RDATA)) res_rd <= res_rd + 32'd1;
            case (st)
            IDLE: if (go_edge) begin
                e_seed <= cfg_seed;
                wbase <= cfg_seed;
                w_left <= cfg_beats;
                r_left <= cfg_beats;
                m_awaddr <= cfg_base;
                m_araddr <= cfg_base;
                res_busy <= 1'b1;
                res_done <= 1'b0;
                res_err <= 1'b0;
                res_mism <= 32'd0;
                res_wr <= 32'd0;
                res_rd <= 32'd0;
                st <= WAW;
            end
            WAW: begin
                m_awvalid <= 1'b1;
                m_awlen <= burst_len;
                burst_beat <= 5'd0;
                st <= WDATA;
                m_wdata <= lanes(wbase);
                m_wlast <= (burst_len == 8'd0);
                m_wvalid <= 1'b1;
            end
            WDATA: begin
                if (m_awready) m_awvalid <= 1'b0;
                if (m_wvalid && m_wready) begin
                    w_left <= w_left - 20'd1;
                    burst_beat <= burst_beat + 5'd1;
                    wbase <= wbase + 32'd8;
                    if (m_wlast) begin
                        m_wvalid <= 1'b0;
                        m_wlast <= 1'b0;
                        m_bready <= 1'b1;
                        st <= WRSP;
                    end else begin
                        m_wdata <= lanes_next(wbase);
                        m_wlast <= ({3'd0, burst_beat} + 8'd1 == m_awlen);
                    end
                end
            end
            WRSP: begin
                if (m_awvalid && m_awready) m_awvalid <= 1'b0;
                if (m_bvalid && !m_awvalid) begin
                    m_bready <= 1'b0;
                    if (m_bresp != 2'b00) res_err <= 1'b1;
                    if (w_left == 20'd0) begin
                        ebase <= e_seed;
                        st <= RAR;
                    end else begin
                        m_awaddr <= m_awaddr + 32'd512;
                        st <= WAW;
                    end
                end
            end
            RAR: begin
                m_arvalid <= 1'b1;
                m_arlen <= burst_len;
                st <= RDATA;
                m_rready <= 1'b1;
            end
            RDATA: begin
                if (m_arready) m_arvalid <= 1'b0;
                if (m_rvalid && m_rready) begin
                    if (m_rresp != 2'b00) res_err <= 1'b1;
                    ebase <= ebase + 32'd8;
                    r_left <= r_left - 20'd1;
                    if (m_rlast) begin
                        m_rready <= 1'b0;
                        if (r_left == 20'd1) begin
                            flush <= 2'd3;
                            st <= FLUSH;
                        end else begin
                            m_araddr <= m_araddr + 32'd512;
                            st <= RAR;
                        end
                    end
                end
            end
            FLUSH: begin   // the last beat is still in the compare and count stages
                flush <= flush - 2'd1;
                if (flush == 2'd1) st <= FIN;
            end
            FIN: begin
                res_busy <= 1'b0;
                res_done <= 1'b1;
                st <= IDLE;
            end
            default: st <= IDLE;
            endcase
        end
    end
endmodule
