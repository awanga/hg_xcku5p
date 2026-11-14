// SPDX-License-Identifier: MIT
// Independent model: the source is a byte array; a job must leave dst[d+i] == src[i] for i < len and every other byte of the
// destination at its sentinel value. The write-channel slave applies the strobes to a byte array. Expected beat count is
// ceil((d%8 + len)/8). Randomised ready/valid stalls on all channels; error injection on a read or a write response.
`timescale 1ns / 1ps
module tb_eth_dma;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    // register port (single driver: the initial block below)
    reg  [4:0]  s_awaddr = 5'd0, s_araddr = 5'd0;
    reg         s_awvalid = 1'b0, s_wvalid = 1'b0, s_arvalid = 1'b0, s_bready = 1'b1, s_rready = 1'b1;
    reg  [31:0] s_wdata = 32'd0;
    wire        s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [1:0]  s_bresp, s_rresp;
    wire [31:0] s_rdata;

    wire [31:0] m_araddr, m_awaddr;
    wire        m_arvalid, m_rready, m_awvalid, m_wvalid, m_bready;
    reg         m_arready = 1'b0, m_rvalid = 1'b0, m_awready = 1'b0, m_wready = 1'b0, m_bvalid = 1'b0;
    reg  [31:0] m_rdata = 32'd0;
    reg  [1:0]  m_rresp = 2'b00, m_bresp = 2'b00;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    wire        irq;

    eth_dma dut (.clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(4'hF),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rvalid(m_rvalid), .m_rready(m_rready),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready), .m_wdata(m_wdata), .m_wstrb(m_wstrb),
        .m_wvalid(m_wvalid), .m_wready(m_wready), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready), .irq(irq));

    // ---- memories
    reg [7:0] src_mem [0:4095];
    reg [7:0] dst_mem [0:4095];
    integer rnd_seed = 1;
    integer stall;           // 0 = never stall, 1 = random stalls
    integer inj_rd = -1;     // read number (0-based) that returns SLVERR, -1 none
    integer inj_wr = -1;     // write beat number that returns SLVERR
    integer rd_count, beat_count, beats_seen_total;

    function rnd_ok;  // returns 1 when the channel may proceed this cycle
        input dummy;
        begin
            if (stall == 0) rnd_ok = 1'b1;
            else rnd_ok = (($random(rnd_seed) & 3) != 0);
        end
    endfunction

    // source slave: one AR at a time, data after a random delay
    reg [31:0] ar_q;
    reg        ar_pending = 1'b0;
    always @(posedge clk) begin
        m_arready <= 1'b0;
        if (m_rvalid && m_rready) m_rvalid <= 1'b0;
        if (!ar_pending && !m_rvalid && m_arvalid && rnd_ok(0)) begin
            m_arready <= 1'b1;
            ar_q <= m_araddr;
            ar_pending <= 1'b1;
        end else if (ar_pending && m_arready == 1'b0 && rnd_ok(0)) begin
            m_rdata <= {src_mem[ar_q + 3], src_mem[ar_q + 2], src_mem[ar_q + 1], src_mem[ar_q]};
            m_rresp <= (rd_count == inj_rd) ? 2'b10 : 2'b00;
            m_rvalid <= 1'b1;
            ar_pending <= 1'b0;
            rd_count <= rd_count + 1;
        end
    end

    // destination slave
    reg aw_got = 1'b0, w_got = 1'b0;
    reg [31:0] aw_q;
    reg [63:0] w_q;
    reg [7:0]  s_q;
    integer lane, protocol_errors = 0;
    always @(posedge clk) begin
        m_awready <= 1'b0;
        m_wready <= 1'b0;
        if (m_bvalid && m_bready) m_bvalid <= 1'b0;
        if (!aw_got && m_awvalid && rnd_ok(0)) begin
            m_awready <= 1'b1;
            aw_q <= m_awaddr;
            aw_got <= 1'b1;
        end
        if (!w_got && m_wvalid && rnd_ok(0)) begin
            m_wready <= 1'b1;
            w_q <= m_wdata;
            s_q <= m_wstrb;
            w_got <= 1'b1;
        end
        if (aw_got && w_got && !m_bvalid) begin
            if (aw_q[2:0] != 3'd0) protocol_errors <= protocol_errors + 1;
            for (lane = 0; lane < 8; lane = lane + 1)
                if (s_q[lane]) dst_mem[{aw_q[31:3], 3'd0} + lane] <= w_q[lane * 8 +: 8];
            m_bresp <= (beat_count == inj_wr) ? 2'b10 : 2'b00;
            m_bvalid <= 1'b1;
            beat_count <= beat_count + 1;
            beats_seen_total <= beats_seen_total + 1;
            aw_got <= 1'b0;
            w_got <= 1'b0;
        end
    end

    // ---- register access (blocking, one driver)
    // Register accesses drive on negedge and look at the ready signals 1 ns before the posedge that takes the handshake, so
    // the result does not depend on whether the simulator resumes this process before or after the DUT's nonblocking updates.
    reg got;
    task wr;
        input [4:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            s_awaddr = a; s_awvalid = 1'b1; s_wdata = d; s_wvalid = 1'b1;
            got = 1'b0;
            while (!got) begin
                #4;
                got = s_awready && s_wready;
                @(negedge clk);
            end
            s_awvalid = 1'b0; s_wvalid = 1'b0;
            while (!s_bvalid) @(negedge clk);
            @(negedge clk);
        end
    endtask
    reg [31:0] rd_val;
    task rd;
        input [4:0] a;
        begin
            @(negedge clk);
            s_araddr = a; s_arvalid = 1'b1;
            got = 1'b0;
            while (!got) begin
                #4;
                got = s_arready;
                @(negedge clk);
            end
            s_arvalid = 1'b0;
            while (!s_rvalid) @(negedge clk);
            rd_val = s_rdata;
            @(negedge clk);
        end
    endtask

    integer errors = 0, checks = 0, i, wd, n;
    task fail;
        input [255:0] what;
        begin
            errors = errors + 1;
            $display("FAIL %0s", what);
        end
    endtask

    // one job; returns after DONE. exp_err: 0 none, 1 read error, 2 write error
    task job;
        input [31:0] sa;
        input [31:0] da;
        input [31:0] ln;
        input integer ierr_rd;
        input integer ierr_wr;
        integer timeout, exp_beats, st_busy, bad;
        reg [31:0] before_done;
        begin
            for (i = 0; i < 4096; i = i + 1) dst_mem[i] = 8'hA5 ^ i[7:0];
            for (i = 0; i < 4096; i = i + 1) src_mem[i] = (i * 37 + 11 + ln) & 255;
            rd_count = 0; beat_count = 0; inj_rd = ierr_rd; inj_wr = ierr_wr;
            wr(5'h00, sa); wr(5'h04, da); wr(5'h08, ln);
            wr(5'h0C, 32'h6);          // clear stale DONE/ERR
            wr(5'h0C, 32'h1);          // start
            timeout = 0;
            rd(5'h0C);
            while (!rd_val[1] && timeout < 20000) begin rd(5'h0C); timeout = timeout + 1; end
            checks = checks + 1;
            if (timeout >= 20000) fail("timeout");
            exp_beats = (da % 8 + ln + 7) / 8;
            bad = 0;
            if (ierr_rd < 0 && ierr_wr < 0) begin
                for (i = 0; i < 4096; i = i + 1) begin
                    if (i >= da && i < da + ln) begin
                        if (dst_mem[i] !== src_mem[sa + i - da]) bad = bad + 1;
                    end else if (dst_mem[i] !== (8'hA5 ^ i[7:0])) bad = bad + 1;
                end
                if (bad != 0) begin $display("  sa=%0d da=%0d len=%0d: %0d byte mismatches", sa, da, ln, bad); fail("data"); end
                if (beat_count != ((ln == 0) ? 0 : exp_beats)) begin
                    $display("  beats %0d expected %0d", beat_count, exp_beats); fail("beats");
                end
                if (rd_val[2]) fail("unexpected ERR");
                if (rd_count != ((ln + 3) / 4)) begin $display("  reads %0d expected %0d", rd_count, (ln + 3) / 4); fail("reads"); end
            end else begin
                if (!rd_val[2]) fail("ERR not set");
            end
            if (rd_val[0]) fail("BUSY with DONE");
            wr(5'h0C, 32'h6);
            rd(5'h0C);
            if (rd_val[2:0] != 3'd0) fail("W1C");
        end
    endtask

    integer sa_i, d_i, l_i;
    initial begin
        stall = 0; rd_count = 0; beat_count = 0; beats_seen_total = 0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        // register read-back and idle status
        wr(5'h00, 32'h1000); wr(5'h04, 32'h2003); wr(5'h08, 32'd77);
        rd(5'h00); if (rd_val !== 32'h1000) fail("SRC readback");
        rd(5'h04); if (rd_val !== 32'h2003) fail("DST readback");
        rd(5'h08); if (rd_val !== 32'd77) fail("LEN readback");
        rd(5'h0C); if (rd_val !== 32'd0) fail("idle status");
        // length 0: DONE, no bus traffic
        job(32'd0, 32'd5, 32'd0, -1, -1);
        for (n = 0; n < 2; n = n + 1) begin
            stall = n;
            // every destination offset and every length 1..40, source word aligned at 0, 8 and 100*4
            for (d_i = 0; d_i < 8; d_i = d_i + 1)
                for (l_i = 1; l_i <= 40; l_i = l_i + 1)
                    job(32'd0 + 8 * (l_i % 3 == 0) + 400 * (l_i % 3 == 1), 32'd1024 + d_i, l_i, -1, -1);
            // packet sized jobs
            job(32'd0, 32'd2 + 1000, 32'd1514, -1, -1);
            job(32'd4, 32'd2000 + 6, 32'd1500, -1, -1);
            job(32'd0, 32'd0, 32'd2048, -1, -1);
        end
        // errors: read error on the 3rd read, on the first; write error on the 2nd beat and the first
        stall = 1;
        job(32'd0, 32'd1026, 32'd64, 2, -1);
        job(32'd0, 32'd1026, 32'd64, 0, -1);
        job(32'd0, 32'd1026, 32'd64, -1, 1);
        job(32'd0, 32'd1026, 32'd64, -1, 0);
        // a job after an error runs normally
        job(32'd0, 32'd1029, 32'd33, -1, -1);
        // start while busy is ignored: second start must not restart the copy
        stall = 1;
        for (i = 0; i < 4096; i = i + 1) dst_mem[i] = 8'hA5 ^ i[7:0];
        for (i = 0; i < 4096; i = i + 1) src_mem[i] = (i * 5 + 3) & 255;
        rd_count = 0; beat_count = 0; inj_rd = -1; inj_wr = -1;
        wr(5'h00, 32'd0); wr(5'h04, 32'd1024); wr(5'h08, 32'd200); wr(5'h0C, 32'h1);
        wr(5'h08, 32'd8); wr(5'h04, 32'd3000); wr(5'h0C, 32'h1);   // ignored: busy
        rd(5'h08); if (rd_val !== 32'd200) fail("LEN written while busy");
        rd(5'h0C);
        while (!rd_val[1]) rd(5'h0C);
        checks = checks + 1;
        if (rd_count != 50) begin $display("  busy-start reads %0d", rd_count); fail("busy start not ignored"); end
        for (i = 0; i < 200; i = i + 1) if (dst_mem[1024 + i] !== src_mem[i]) fail("busy-start data");
        if (dst_mem[3000] !== (8'hA5 ^ 8'd184)) fail("busy start wrote elsewhere");
        wr(5'h0C, 32'h6);
        // interrupt: level held until DONE cleared, gated by IEN
        wr(5'h08, 32'd16); wr(5'h04, 32'd1024); wr(5'h00, 32'd0);
        wr(5'h10, 32'd0); wr(5'h0C, 32'h1);
        rd(5'h0C); while (!rd_val[1]) rd(5'h0C);
        checks = checks + 1;
        if (irq) fail("irq without IEN");
        wr(5'h10, 32'd1);
        repeat (3) @(posedge clk);
        if (!irq) fail("irq not raised");
        repeat (50) @(posedge clk);
        if (!irq) fail("irq not held");
        wr(5'h0C, 32'h2);
        repeat (3) @(posedge clk);
        if (irq) fail("irq not cleared");
        if (protocol_errors != 0) fail("unaligned AW address");
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
    initial begin
        #200000000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
