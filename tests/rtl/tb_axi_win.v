// SPDX-License-Identifier: MIT
// axi_win: window [0x1000, 0x3000). Independent model: a byte array behind the master port plus a count of the address handshakes it sees.
// A burst entirely inside the window must read back what was written and be seen by the slave; every other burst must get DECERR (writes: one B,
// reads: len+1 beats with rlast on the last), leave the array at its sentinel and produce no address handshake downstream.
`timescale 1ns / 1ps
module tb_axi_win;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    parameter STALL = 1;

    reg  [31:0] win_base = 32'h1000, win_size = 32'h2000;
    // slave-side (TB is the PCIe master)
    reg  [3:0]  s_awid = 0, s_arid = 0;
    reg  [31:0] s_awaddr = 0, s_araddr = 0;
    reg         s_awhi = 0, s_arhi = 0;
    reg  [7:0]  s_awlen = 0, s_arlen = 0;
    reg  [2:0]  s_awsize = 3'd3, s_arsize = 3'd3;
    reg  [1:0]  s_awburst = 2'b01, s_arburst = 2'b01;
    reg         s_awvalid = 0, s_wvalid = 0, s_bready = 0, s_arvalid = 0, s_rready = 0, s_wlast = 0;
    reg  [63:0] s_wdata = 0;
    reg  [7:0]  s_wstrb = 8'hFF;
    wire        s_awready, s_wready, s_bvalid, s_arready, s_rvalid, s_rlast;
    wire [3:0]  s_bid, s_rid;
    wire [1:0]  s_bresp, s_rresp;
    wire [63:0] s_rdata;
    // master-side
    wire [3:0]  m_awid, m_arid;
    wire [31:0] m_awaddr, m_araddr;
    wire [7:0]  m_awlen, m_arlen;
    wire [2:0]  m_awsize, m_arsize;
    wire [1:0]  m_awburst, m_arburst;
    wire        m_awvalid, m_wvalid, m_wlast, m_bready, m_arvalid, m_rready;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    reg         m_awready = 0, m_bvalid = 0, m_arready = 0, m_rvalid = 0, m_rlast = 0;
    reg  [3:0]  m_bid = 0, m_rid = 0;
    reg  [1:0]  m_bresp = 0, m_rresp = 0;
    reg         m_wready;
    reg  [63:0] m_rdata = 0;

    axi_win dut (.clk(clk), .rst_n(rst_n), .win_base(win_base), .win_size(win_size),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awhi(s_awhi), .s_awlen(s_awlen), .s_awsize(s_awsize), .s_awburst(s_awburst),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arhi(s_arhi), .s_arlen(s_arlen), .s_arsize(s_arsize), .s_arburst(s_arburst),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rlast(s_rlast),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awvalid(m_awvalid),
        .m_awready(m_awready), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast), .m_rvalid(m_rvalid),
        .m_rready(m_rready));

    // ---- downstream slave model (random stalls)
    reg [7:0] mem [0:16383];
    parameter SEED = 7;
    integer seed = SEED;
    integer aw_seen = 0, ar_seen = 0, w_beats = 0;
    function ok;
        input d;
        begin ok = (STALL == 0) ? 1'b1 : (($random(seed) & 3) != 0); end
    endfunction
    reg [31:0] wa;
    reg [7:0]  wl;
    reg [3:0]  wid;
    reg        w_active = 0, b_pend = 0;
    integer    wcnt, k;
    reg rnd_w = 1'b0;
    always @(posedge clk) rnd_w <= ok(0);
    always @* m_wready = w_active && rnd_w;
    always @(posedge clk) begin
        m_awready <= 1'b0;
        if (m_bvalid && m_bready) m_bvalid <= 1'b0;
        if (!w_active && !b_pend && m_awvalid && ok(0) && !m_awready) begin
            m_awready <= 1'b1;
            wa <= m_awaddr; wl <= m_awlen; wid <= m_awid;
            w_active <= 1'b1; wcnt <= 0;
            aw_seen <= aw_seen + 1;
            if (m_awid !== 4'd0) begin $display("FAIL downstream awid not 0"); errors = errors + 1; end
            if (m_awsize !== 3'd3 || m_awburst !== 2'b01) begin $display("FAIL awsize/burst not forwarded"); errors = errors + 1; end
        end else if (w_active && m_wvalid && m_wready) begin
            for (k = 0; k < 8; k = k + 1) if (m_wstrb[k]) mem[(wa + 8 * wcnt + k) & 16383] <= m_wdata[8 * k +: 8];
            wcnt <= wcnt + 1;
            w_beats <= w_beats + 1;
            if (m_wlast) begin
                w_active <= 1'b0; b_pend <= 1'b1;
                if (wcnt != wl) begin $display("FAIL wlast at beat %0d of %0d", wcnt, wl); errors = errors + 1; end
            end
        end else if (b_pend && ok(0)) begin
            m_bvalid <= 1'b1; m_bid <= wid; m_bresp <= 2'b00; b_pend <= 1'b0;
        end
    end
    reg [31:0] ra;
    reg [7:0]  rl;
    reg [3:0]  rid_q;
    reg        r_active = 0;
    integer    rcnt, j;
    always @(posedge clk) begin
        m_arready <= 1'b0;
        if (m_rvalid && m_rready) begin
            m_rvalid <= 1'b0;
            if (m_rlast) r_active <= 1'b0;
        end
        if (!r_active && m_arvalid && ok(0) && !m_arready) begin
            m_arready <= 1'b1;
            ra <= m_araddr; rl <= m_arlen; rid_q <= m_arid;
            r_active <= 1'b1; rcnt <= 0;
            ar_seen <= ar_seen + 1;
            if (m_arid !== 4'd0) begin $display("FAIL downstream arid not 0"); errors = errors + 1; end
        end else if (r_active && (!m_rvalid || m_rready) && !(m_rvalid && m_rlast) && ok(0) && rcnt <= rl && !m_arready) begin
            for (j = 0; j < 8; j = j + 1) m_rdata[8 * j +: 8] <= mem[(ra + 8 * rcnt + j) & 16383];
            m_rid <= rid_q; m_rresp <= 2'b00; m_rlast <= (rcnt == rl); m_rvalid <= 1'b1;
            rcnt <= rcnt + 1;
        end
    end

    integer errors = 0, checks = 0;
    task chk(input [255:0] what, input cond);
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FAIL %0s", what); end end
    endtask

    function [63:0] pat(input [31:0] a, input integer i);
        reg [31:0] t;
        begin
            t = i * 3 + 1;
            pat = {a[15:0] ^ 16'h5a5a, i[15:0], ~a[15:0], t[15:0]};
        end
    endfunction

    // master tasks (the only drivers of s_aw*/s_w*/s_b* and s_ar*/s_r* respectively)
    reg [1:0] last_bresp, last_rresp_all;
    integer   last_beats, last_rlast_ok;
    reg [3:0] last_bid, last_rid_seen;
    // Handshakes are decided between clock edges (the DUT outputs are stable after the edge plus 1 ns): a ready/valid pair that is high
    // together at that point transfers at the next rising edge. Sampling at the edge itself would race with the DUT's own update.
    task wr(input [3:0] id, input [31:0] a, input [7:0] len, input hi);
        integer i;
        begin
            @(negedge clk);
            s_awid = id; s_awaddr = a; s_awlen = len; s_awhi = hi; s_awvalid = 1'b1;
            #1; while (!s_awready) begin @(negedge clk); #1; end
            @(posedge clk);
            @(negedge clk); s_awvalid = 1'b0; s_awhi = 1'b0;
            for (i = 0; i <= len; i = i + 1) begin
                if (STALL && (($random(seed) & 3) == 0)) repeat (2) @(negedge clk);
                s_wdata = pat(a, i); s_wlast = (i == len); s_wvalid = 1'b1;
                #1; while (!s_wready) begin @(negedge clk); #1; end
                @(posedge clk);
                @(negedge clk); s_wvalid = 1'b0; s_wlast = 1'b0;
            end
            s_bready = 1'b1;
            #1; while (!s_bvalid) begin @(negedge clk); #1; end
            last_bresp = s_bresp; last_bid = s_bid;
            @(posedge clk);
            @(negedge clk); s_bready = 1'b0;
        end
    endtask
    task rd(input [3:0] id, input [31:0] a, input [7:0] len, input hi);
        integer n;
        reg done;
        begin
            @(negedge clk);
            s_arid = id; s_araddr = a; s_arlen = len; s_arhi = hi; s_arvalid = 1'b1;
            #1; while (!s_arready) begin @(negedge clk); #1; end
            @(posedge clk);
            @(negedge clk); s_arvalid = 1'b0; s_arhi = 1'b0;
            n = 0; last_rresp_all = 2'b00; last_rlast_ok = 1; done = 1'b0;
            s_rready = 1'b1;
            #1;
            while (!done) begin
                while (!s_rvalid) begin @(negedge clk); #1; end
                if (n == 0 || s_rresp != 2'b00) last_rresp_all = s_rresp;
                last_rid_seen = s_rid;
                if (s_rresp == 2'b00 && s_rdata !== pat(a, n)) begin errors = errors + 1; $display("FAIL read data beat %0d", n); end
                if (s_rlast !== (n == len)) last_rlast_ok = 0;
                n = n + 1;
                done = s_rlast;
                @(posedge clk);
                @(negedge clk); #1;
            end
            last_beats = n;
            s_rready = 1'b0;
        end
    endtask

    integer sa, sr, sw, i;
    reg [63:0] pat0;
    task expect_ok_wr(input [3:0] id, input [31:0] a, input [7:0] len);
        begin
            sa = aw_seen;
            wr(id, a, len, 1'b0);
            chk("in-window write: OKAY", last_bresp == 2'b00);
            chk("in-window write: id echoed", last_bid == id);
            chk("in-window write: AW reached the slave", aw_seen == sa + 1);
        end
    endtask
    task expect_err_wr(input [3:0] id, input [31:0] a, input [7:0] len, input hi);
        begin
            sa = aw_seen; sw = w_beats;
            wr(id, a, len, hi);
            chk("refused write: DECERR", last_bresp == 2'b11);
            chk("refused write: id echoed", last_bid == id);
            chk("refused write: nothing reached the slave", aw_seen == sa && w_beats == sw);
        end
    endtask
    task expect_ok_rd(input [3:0] id, input [31:0] a, input [7:0] len);
        begin
            sr = ar_seen;
            rd(id, a, len, 1'b0);
            chk("in-window read: OKAY", last_rresp_all == 2'b00);
            chk("in-window read: beats", last_beats == len + 1);
            chk("in-window read: rlast only on the last beat", last_rlast_ok == 1);
            chk("in-window read: id echoed", last_rid_seen == id);
            chk("in-window read: AR reached the slave", ar_seen == sr + 1);
        end
    endtask
    task expect_err_rd(input [3:0] id, input [31:0] a, input [7:0] len, input hi);
        begin
            sr = ar_seen;
            rd(id, a, len, hi);
            chk("refused read: DECERR", last_rresp_all == 2'b11);
            chk("refused read: beats", last_beats == len + 1);
            chk("refused read: rlast only on the last beat", last_rlast_ok == 1);
            chk("refused read: id echoed", last_rid_seen == id);
            chk("refused read: nothing reached the slave", ar_seen == sr);
        end
    endtask

    initial begin
        for (i = 0; i < 16384; i = i + 1) mem[i] = 8'hEE;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // inside: first 8 bytes, a long burst, last 8 bytes; read each back (the slave array holds what the master wrote)
        expect_ok_wr(4'd1, 32'h1000, 8'd0);
        expect_ok_rd(4'd1, 32'h1000, 8'd0);
        expect_ok_wr(4'd2, 32'h1800, 8'd31);
        expect_ok_rd(4'd2, 32'h1800, 8'd31);
        expect_ok_wr(4'd3, 32'h2FF8, 8'd0);
        expect_ok_rd(4'd3, 32'h2FF8, 8'd0);
        expect_ok_wr(4'd4, 32'h2800, 8'd255);   // 2 KiB ending exactly at 0x2FFF
        expect_ok_rd(4'd4, 32'h2800, 8'd255);
        // just outside: before the start, across the start, across the end, at the end, far away
        expect_err_wr(4'd5, 32'h0FF8, 8'd0, 1'b0);
        expect_err_wr(4'd6, 32'h0FF8, 8'd1, 1'b0);
        expect_err_wr(4'd7, 32'h2FF8, 8'd1, 1'b0);
        expect_err_wr(4'd8, 32'h3000, 8'd0, 1'b0);
        expect_err_wr(4'd9, 32'h2808, 8'd255, 1'b0);
        expect_err_wr(4'd10, 32'h0000, 8'd7, 1'b0);
        expect_err_wr(4'd10, 32'h2FF9, 8'd0, 1'b0);   // last byte is the first one past the end (unaligned start)
        expect_ok_wr(4'd10, 32'h2FF8, 8'd0);
        expect_err_rd(4'd5, 32'h0FF8, 8'd0, 1'b0);
        expect_err_rd(4'd6, 32'h0FF8, 8'd1, 1'b0);
        expect_err_rd(4'd7, 32'h2FF8, 8'd1, 1'b0);
        expect_err_rd(4'd8, 32'h3000, 8'd0, 1'b0);
        expect_err_rd(4'd9, 32'h2808, 8'd255, 1'b0);
        expect_err_rd(4'd10, 32'hFFFF_F000, 8'd3, 1'b0);
        expect_err_rd(4'd10, 32'h2FF9, 8'd0, 1'b0);
        // a nonzero upper address is outside whatever the low bits say
        expect_err_wr(4'd11, 32'h1800, 8'd3, 1'b1);
        expect_err_rd(4'd11, 32'h1800, 8'd3, 1'b1);
        // an error burst between good ones does not disturb the next one
        expect_ok_wr(4'd12, 32'h2000, 8'd7);
        expect_err_wr(4'd13, 32'h4000, 8'd7, 1'b0);
        expect_ok_rd(4'd14, 32'h2000, 8'd7);
        // the sentinel is intact outside the window and the written data is exact inside
        chk("sentinel below the window", mem[32'h0FF8] == 8'hEE && mem[32'h0FFF] == 8'hEE);
        chk("sentinel above the window", mem[32'h3000] == 8'hEE && mem[32'h3007] == 8'hEE);
        pat0 = pat(32'h1000, 0);
        chk("first written byte of 0x1000", mem[32'h1000] == pat0[7:0]);
        // read and write directions concurrently
        fork
            expect_ok_wr(4'd1, 32'h1400, 8'd15);
            expect_ok_rd(4'd2, 32'h1800, 8'd15);
        join
        // closing the window refuses everything, reopening restores it
        win_size = 32'd0;
        expect_err_wr(4'd3, 32'h1000, 8'd0, 1'b0);
        expect_err_rd(4'd3, 32'h1000, 8'd0, 1'b0);
        win_size = 32'h2000;
        expect_ok_rd(4'd4, 32'h1000, 8'd0);
        // a different window position
        win_base = 32'h2000; win_size = 32'h400;
        expect_ok_wr(4'd5, 32'h2000, 8'd3);
        expect_err_wr(4'd5, 32'h1FF8, 8'd0, 1'b0);
        expect_ok_wr(4'd5, 32'h23F8, 8'd0);
        expect_err_wr(4'd5, 32'h23F8, 8'd1, 1'b0);
        expect_err_rd(4'd5, 32'h2400, 8'd0, 1'b0);
        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (errors == 0 && checks > 100) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin #20000000; $display("TBRESULT timeout FAIL"); $finish; end
endmodule
