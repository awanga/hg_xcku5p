// SPDX-License-Identifier: MIT
// vdma: a register-bus master (the driver) and a byte-array AXI4 memory (host memory in 0..0x3FFFF, card memory from 0x40000, the window 0x40000..0x5FFFF).
// Expected values are computed from the descriptor program and the byte pattern pb(address), never from the DUT. Slave handshakes are decided at the
// falling clock edge from signals that cannot change before the next rising edge.
`timescale 1ns / 1ps
module tb_vdma;
    parameter LAT = 0;   // extra wait states on the memory side
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [15:0] s_awaddr = 16'd0, s_araddr = 16'd0;
    reg  [31:0] s_wdata = 32'd0;
    reg         s_awvalid = 1'b0, s_wvalid = 1'b0, s_arvalid = 1'b0;
    wire        s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [31:0] s_rdata;
    wire [31:0] m_awaddr, m_araddr;
    wire [7:0]  m_awlen, m_arlen;
    wire [63:0] m_wdata;
    reg  [63:0] m_rdata = 64'd0;
    wire        m_awvalid, m_wlast, m_wvalid, m_bready, m_arvalid, m_rready;
    reg         m_awready = 1'b0, m_wready = 1'b0, m_bvalid = 1'b0, m_arready = 1'b0, m_rlast = 1'b0, m_rvalid = 1'b0;
    reg  [1:0]  m_bresp = 2'b00, m_rresp = 2'b00;
    reg  [31:0] win_base = 32'd0, win_size = 32'd0;
    reg         user_req = 1'b0;
    wire        intx;

    vdma dut (.clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(4'hF), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bresp(), .s_bvalid(s_bvalid), .s_bready(1'b1), .s_araddr(s_araddr), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(), .s_rvalid(s_rvalid), .s_rready(1'b1),
        .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awvalid(m_awvalid), .m_awready(m_awready), .m_wdata(m_wdata), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arvalid(m_arvalid), .m_arready(m_arready), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready),
        .win_base(win_base), .win_size(win_size), .user_req(user_req), .intx(intx));

    // ------------------------------------------------------------- memory model
    reg [7:0] mb [0:524287];
    integer seed = 12345;
    reg [31:0] rerr_addr = 32'hFFFFFFFF, werr_addr = 32'hFFFFFFFF;   // a burst at this address gets SLVERR
    integer wr_bursts = 0, rd_bursts = 0, max_len = 0, bad_bursts = 0;
    reg [31:0] ra_q, wa_q;
    integer rbeats, rcnt, wcnt, rgap, wgap;
    reg        rbusy = 1'b0, wbusy = 1'b0, wdone = 1'b0, r_fire = 1'b0, b_fire = 1'b0, werr_now = 1'b0, rerr_now = 1'b0;
    integer k;
    function [7:0] pb(input [31:0] a);
        pb = a[7:0] ^ (a[15:8] * 3) ^ (a[19:16] * 17) ^ 8'h5A;
    endfunction
    function [7:0] pc(input [31:0] a);
        pc = ~pb(a) ^ 8'h33;
    endfunction
    function integer gap(input integer x);
        gap = (LAT == 0) ? 0 : ($random(seed) & 3) * LAT;
    endfunction
    always @(negedge clk) begin
        // ---- read channel: AR accepted, then R beats with gaps
        m_arready = 1'b0;
        if (!rbusy) begin
            if (m_arvalid && ($random(seed) & 1 || LAT == 0)) begin
                m_arready = 1'b1;
                ra_q = m_araddr;
                rbeats = m_arlen + 1;
                rcnt = 0;
                rgap = gap(0);
                rbusy = 1'b1;
                rd_bursts = rd_bursts + 1;
                if (m_araddr[11:0] + (m_arlen + 1) * 8 > 4096) bad_bursts = bad_bursts + 1;
                if (m_arlen + 1 > max_len) max_len = m_arlen + 1;
                rerr_now = (m_araddr == rerr_addr);
                m_rvalid = 1'b0;
                r_fire = 1'b0;
            end
        end else begin
            if (r_fire) begin   // the previous beat was taken at the last rising edge
                rcnt = rcnt + 1;
                m_rvalid = 1'b0;
                r_fire = 1'b0;
                if (rcnt == rbeats) rbusy = 1'b0;
                rgap = gap(0);
            end
            if (rbusy && !r_fire) begin
                if (rgap > 0) rgap = rgap - 1;
                else begin
                    for (k = 0; k < 8; k = k + 1) m_rdata[8*k +: 8] = mb[(ra_q + rcnt * 8 + k) & 32'h7FFFF];
                    m_rlast = (rcnt == rbeats - 1);
                    m_rresp = rerr_now ? 2'b10 : 2'b00;
                    m_rvalid = 1'b1;
                    r_fire = m_rready;
                end
            end
        end
        // ---- write channel
        m_awready = 1'b0; m_wready = 1'b0;
        if (!wbusy) begin
            if (m_awvalid && ($random(seed) & 1 || LAT == 0)) begin
                m_awready = 1'b1;
                wa_q = m_awaddr;
                wcnt = 0;
                wbusy = 1'b1;
                wdone = 1'b0;
                wr_bursts = wr_bursts + 1;
                if (m_awaddr[11:0] + (m_awlen + 1) * 8 > 4096) bad_bursts = bad_bursts + 1;
                if (m_awlen + 1 > max_len) max_len = m_awlen + 1;
                werr_now = (m_awaddr == werr_addr);
            end
        end else if (!wdone) begin
            if (m_wvalid && ($random(seed) & 1 || LAT == 0)) begin
                m_wready = 1'b1;
                if (!werr_now) for (k = 0; k < 8; k = k + 1) mb[(wa_q + wcnt * 8 + k) & 32'h7FFFF] = m_wdata[8*k +: 8];
                wcnt = wcnt + 1;
                if (m_wlast) wdone = 1'b1;
            end
        end else begin
            if (b_fire) begin   // taken at the last rising edge
                m_bvalid = 1'b0;
                b_fire = 1'b0;
                wbusy = 1'b0;
            end else begin
                m_bresp = werr_now ? 2'b10 : 2'b00;
                m_bvalid = 1'b1;
                b_fire = m_bready;
            end
        end
    end

    // ------------------------------------------------------------- register bus
    integer errors = 0, checks = 0;
    reg [31:0] rd_val;
    task rw(input [15:0] a, input [31:0] d);
        begin
            @(negedge clk); s_awaddr = a; s_wdata = d; s_awvalid = 1'b1; s_wvalid = 1'b1;
            @(posedge clk); while (!(s_awready && s_wready)) @(posedge clk);
            @(negedge clk); s_awvalid = 1'b0; s_wvalid = 1'b0;
            @(posedge clk); while (!s_bvalid) @(posedge clk);
        end
    endtask
    task rr(input [15:0] a);
        begin
            @(negedge clk); s_araddr = a; s_arvalid = 1'b1;
            @(posedge clk); while (!s_arready) @(posedge clk);
            @(negedge clk); s_arvalid = 1'b0;
            @(posedge clk); while (!s_rvalid) @(posedge clk);
            #1 rd_val = s_rdata;
        end
    endtask
    task ev(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            checks = checks + 1;
            if (got !== want) begin errors = errors + 1; $display("FAIL %0s: got %08x want %08x", what, got, want); end
        end
    endtask

    // ------------------------------------------------------------- driver helpers
    task put32(input [31:0] a, input [31:0] d);
        begin mb[a] = d[7:0]; mb[a + 1] = d[15:8]; mb[a + 2] = d[23:16]; mb[a + 3] = d[31:24]; end
    endtask
    task put_desc(input [31:0] a, input [31:0] ctrl, input [31:0] len, input [31:0] src, input [31:0] dst, input [31:0] nxt);
        begin
            put32(a, ctrl); put32(a + 4, len); put32(a + 8, src); put32(a + 12, 32'd0);
            put32(a + 16, dst); put32(a + 20, 32'd0); put32(a + 24, nxt); put32(a + 28, 32'd0);
        end
    endtask
    task fill(input [31:0] a, input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) mb[a + i] = pb(a + i); end
    endtask
    // dst bytes must equal the source pattern; the 16 bytes either side must be untouched
    task check_copy(input [255:0] what, input [31:0] src, input [31:0] dst, input integer n);
        integer i, bad;
        begin
            bad = 0;
            for (i = 0; i < n; i = i + 1) if (mb[dst + i] !== pb(src + i)) bad = bad + 1;
            for (i = 1; i <= 16; i = i + 1) begin
                if (mb[dst - i] !== pc(dst - i)) bad = bad + 1;
                if (mb[dst + n - 1 + i] !== pc(dst + n - 1 + i)) bad = bad + 1;
            end
            ev(what, bad, 0);
        end
    endtask
    task check_untouched(input [255:0] what, input [31:0] dst, input integer n);
        integer i, bad;
        begin
            bad = 0;
            for (i = 0; i < n; i = i + 1) if (mb[dst + i] !== pc(dst + i)) bad = bad + 1;
            ev(what, bad, 0);
        end
    endtask
    task start(input integer ch, input [31:0] d, input [31:0] ctl);
        begin
            rw(ch ? 16'h5080 : 16'h4080, d);
            rw(ch ? 16'h5084 : 16'h4084, 32'd0);
            rw(ch ? 16'h1004 : 16'h0004, ctl);
        end
    endtask
    integer wt;
    task wait_idle(input integer ch);
        begin
            wt = 0;
            rr(ch ? 16'h1040 : 16'h0040);
            while (rd_val[0] && wt < 4000) begin rr(ch ? 16'h1040 : 16'h0040); wt = wt + 1; end
            ev("engine went idle", wt < 4000, 1);
        end
    endtask
    task stop(input integer ch);
        rw(ch ? 16'h1004 : 16'h0004, 32'd0);
    endtask
    // status value after a transfer (read-clears): latched bits only
    task get_status(input integer ch);
        rr(ch ? 16'h1044 : 16'h0044);
    endtask

    integer i, n0;
    initial begin
        for (i = 0; i < 524288; i = i + 1) mb[i] = pc(i);
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // identifiers and constants
        rr(16'h0000); ev("H2C id", rd_val, 32'h1FC00006);
        rr(16'h1000); ev("C2H id", rd_val, 32'h1FC10006);
        rr(16'h2000); ev("IRQ id", rd_val, 32'h1FC20006);
        rr(16'h3000); ev("config id", rd_val, 32'h1FC30006);
        rr(16'h4000); ev("H2C SGDMA id", rd_val, 32'h1FC40006);
        rr(16'h5000); ev("C2H SGDMA id", rd_val, 32'h1FC50006);
        rr(16'h6000); ev("common id", rd_val, 32'h1FC60006);
        rr(16'h004C); ev("alignments", rd_val, 32'h00080820);
        rr(16'h0040); ev("H2C idle status", rd_val, 32'd0);
        rr(16'h0004); ev("control reset", rd_val, 32'd0);
        rw(16'h0004, 32'hFFFFFFFE); rr(16'h0004); ev("control writable mask (run bit left clear)", rd_val, 32'h06FFFE7E);
        rw(16'h0004, 32'd0);
        rw(16'h0008, 32'h00000006); rw(16'h000C, 32'h00000002); rr(16'h0004); ev("control W1S/W1C", rd_val, 32'h00000004);
        rw(16'h0004, 32'd0);

        // closed window (reset state): an H2C into card memory is refused and writes nothing
        fill(32'h1000, 256);
        put_desc(32'h100, 32'hAD4B0003, 32'd128, 32'h1000, 32'h40100, 32'd0);
        start(0, 32'h100, 32'h1);
        wait_idle(0); get_status(0); ev("closed window: write error only", rd_val, 32'h00004000);
        check_untouched("closed window: nothing written", 32'h40100, 128);
        stop(0);

        win_base = 32'h00040000; win_size = 32'h00020000;
        // H2C, one descriptor, stop + completed
        start(0, 32'h100, 32'h1);
        wait_idle(0); get_status(0); ev("H2C status: completed + stopped", rd_val, 32'h00000006);
        rr(16'h0048); ev("H2C count", rd_val, 32'd1);
        check_copy("H2C 128 bytes", 32'h1000, 32'h40100, 128);
        get_status(0); ev("status read cleared the events", rd_val, 32'd0);
        stop(0);

        // C2H
        fill(32'h40200, 256);
        put_desc(32'h140, 32'hAD4B0003, 32'd256, 32'h40200, 32'h2000, 32'd0);
        start(1, 32'h140, 32'h1);
        wait_idle(1); get_status(1); ev("C2H status", rd_val, 32'h00000006);
        rr(16'h1048); ev("C2H count", rd_val, 32'd1);
        check_copy("C2H 256 bytes", 32'h40200, 32'h2000, 256);
        stop(1);

        // chain of three H2C descriptors: odd length, 4 KiB crossing source, long; the last has the stop bit
        fill(32'h3FF8, 72); fill(32'h5000, 1000);
        put_desc(32'h200, 32'hAD4B0002, 32'd72, 32'h3FF8, 32'h41008, 32'h220);   // not stop: next
        put_desc(32'h220, 32'hAD4B0002, 32'd1000, 32'h5000, 32'h41FF8, 32'h240); // dst crosses 4 KiB
        put_desc(32'h240, 32'hAD4B0003, 32'd8, 32'h3FFC & 32'hFFFFFFF8, 32'h43000, 32'd0);
        start(0, 32'h200, 32'h1);
        wait_idle(0); get_status(0); ev("chain status", rd_val, 32'h00000006);
        rr(16'h0048); ev("chain count", rd_val, 32'd3);
        check_copy("chain 72 bytes (src crosses 4 KiB)", 32'h3FF8, 32'h41008, 72);
        check_copy("chain 1000 bytes (dst crosses 4 KiB)", 32'h5000, 32'h41FF8, 1000);
        check_copy("chain 8 bytes", 32'h3FF8, 32'h43000, 8);
        stop(0);

        // window edges: ends exactly at the window end (allowed), one word over (refused), starts below the base (refused)
        fill(32'h6000, 256);
        put_desc(32'h260, 32'hAD4B0003, 32'd128, 32'h6000, 32'h5FF80, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("window end exact", rd_val, 32'h00000006);
        check_copy("window end exact data", 32'h6000, 32'h5FF80, 128);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd256, 32'h6000, 32'h5FF08, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("one word past the window", rd_val, 32'h00004000);
        check_untouched("one word past: nothing written", 32'h5FF08, 120);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h6000, 32'h3FFF8, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("below the window", rd_val, 32'h00004000);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h3FFF8, 32'h6000, 32'd0);   // C2H source below the window
        start(1, 32'h260, 32'h1); wait_idle(1); get_status(1); ev("C2H source below the window", rd_val, 32'h00000200);
        stop(1);
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h5FFF8, 32'h6000, 32'd0);   // C2H source runs past the end
        start(1, 32'h260, 32'h1); wait_idle(1); get_status(1); ev("C2H source past the end", rd_val, 32'h00000200);
        stop(1);
        // the window does not apply to the host side: H2C source and C2H destination outside it are fine (checked above: 0x1000, 0x2000)

        // the window starts exactly at its base
        put_desc(32'h260, 32'hAD4B0003, 32'd64, 32'h6000, 32'h40000, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("window start exact", rd_val, 32'h00000006);
        check_copy("window start exact data", 32'h6000, 32'h40000, 64);
        stop(0);

        // descriptor errors
        put_desc(32'h260, 32'hAD4A0003, 32'd16, 32'h6000, 32'h40000, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("bad magic", rd_val, 32'h00000010);
        rr(16'h0048); ev("bad magic count", rd_val, 32'd0);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd0, 32'h6000, 32'h40000, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("zero length", rd_val, 32'h00000020);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd12, 32'h6000, 32'h40000, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("length not a multiple of 8", rd_val, 32'h00000008);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h6004, 32'h40000, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("source not 8-aligned", rd_val, 32'h00000008);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h6000, 32'h40004, 32'd0);
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("destination not 8-aligned", rd_val, 32'h00000008);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h6000, 32'h40000, 32'd0); put32(32'h26C, 32'd1);   // source above 4 GiB
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("host source above 4 GiB", rd_val, 32'h00000200);
        stop(0);
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h40000, 32'h6000, 32'd0); put32(32'h274, 32'd1);   // C2H destination above 4 GiB
        start(1, 32'h260, 32'h1); wait_idle(1); get_status(1); ev("host destination above 4 GiB", rd_val, 32'h00004000);
        stop(1);
        rw(16'h4084, 32'd1); rw(16'h0004, 32'h1); wait_idle(0); get_status(0); ev("descriptor address above 4 GiB", rd_val, 32'h00080000);
        stop(0); rw(16'h4084, 32'd0);

        // AXI errors: descriptor fetch, data read, data write
        put_desc(32'h260, 32'hAD4B0003, 32'd64, 32'h6000, 32'h44000, 32'd0);
        rerr_addr = 32'h260;
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("descriptor fetch error", rd_val, 32'h00080000);
        stop(0); rerr_addr = 32'hFFFFFFFF;
        rerr_addr = 32'h6000;
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("data read error", rd_val, 32'h00000200);
        check_untouched("read error: nothing written", 32'h44000, 64);
        stop(0); rerr_addr = 32'hFFFFFFFF;
        werr_addr = 32'h44000;
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("data write error", rd_val, 32'h00004000);
        rr(16'h0048); ev("write error count", rd_val, 32'd0);
        stop(0); werr_addr = 32'hFFFFFFFF;
        // an error leaves the engine usable
        start(0, 32'h260, 32'h1); wait_idle(0); get_status(0); ev("after errors: completes", rd_val, 32'h00000006);
        check_copy("after errors: data", 32'h6000, 32'h44000, 64);
        stop(0);

        // restart: the count restarts at 1
        start(0, 32'h260, 32'h1); wait_idle(0); rr(16'h0048); ev("restart count", rd_val, 32'd1); get_status(0);
        stop(0);

        // interrupts: control enables, IRQ block channel enable, status read clears
        put_desc(32'h260, 32'hAD4B0003, 32'd16, 32'h6000, 32'h45000, 32'd0);
        start(0, 32'h260, 32'h1 | 32'h4);   // run + ie_descriptor_completed
        wait_idle(0);
        ev("no interrupt without the channel enable", {31'd0, intx}, 32'd0);
        rr(16'h2044); ev("channel request", rd_val, 32'h1);
        rr(16'h204C); ev("channel pending masked", rd_val, 32'h0);
        rw(16'h2014, 32'h1); rr(16'h2010); ev("channel enable W1S", rd_val, 32'h1);
        rr(16'h204C); ev("channel pending", rd_val, 32'h1);
        ev("interrupt", {31'd0, intx}, 32'd1);
        get_status(0); ev("event status", rd_val, 32'h00000006);
        ev("interrupt cleared by the status read", {31'd0, intx}, 32'd0);
        stop(0);
        // an event whose enable is not set does not interrupt
        start(0, 32'h260, 32'h1 | 32'h2);   // run + ie_descriptor_stopped only: completed (4) is not enabled but stopped (2) is
        wait_idle(0); ev("interrupt on the stop event", {31'd0, intx}, 32'd1); get_status(0);
        stop(0);
        rw(16'h2018, 32'h1);
        start(0, 32'h260, 32'h1 | 32'h4); wait_idle(0);
        ev("channel disabled again", {31'd0, intx}, 32'd0); get_status(0); stop(0);
        // user interrupt (the CPU doorbell)
        user_req = 1'b1; @(negedge clk);
        ev("user request without enable", {31'd0, intx}, 32'd0);
        rr(16'h2040); ev("user request register", rd_val, 32'h1);
        rr(16'h2048); ev("user pending masked", rd_val, 32'h0);
        rw(16'h2008, 32'h1); @(negedge clk);
        ev("user interrupt", {31'd0, intx}, 32'd1);
        rr(16'h2048); ev("user pending", rd_val, 32'h1);
        user_req = 1'b0; @(negedge clk);
        ev("user interrupt follows the request", {31'd0, intx}, 32'd0);
        rw(16'h200C, 32'h1);

        // both channels started together: both complete, H2C first
        fill(32'h7000, 64); fill(32'h40800, 64);
        put_desc(32'h280, 32'hAD4B0003, 32'd64, 32'h7000, 32'h40400, 32'd0);
        put_desc(32'h2A0, 32'hAD4B0003, 32'd64, 32'h40800, 32'h7800, 32'd0);
        rw(16'h4080, 32'h280); rw(16'h4084, 32'd0); rw(16'h5080, 32'h2A0); rw(16'h5084, 32'd0);
        rw(16'h0004, 32'h1); rw(16'h1004, 32'h1);
        wait_idle(0); wait_idle(1);
        check_copy("simultaneous H2C", 32'h7000, 32'h40400, 64);
        check_copy("simultaneous C2H", 32'h40800, 32'h7800, 64);
        get_status(0); get_status(1); stop(0); stop(1);

        // clearing run mid-chain stops after the current descriptor
        fill(32'h8000, 2048);
        put_desc(32'h2C0, 32'hAD4B0002, 32'd2048, 32'h8000, 32'h46000, 32'h2E0);
        put_desc(32'h2E0, 32'hAD4B0003, 32'd64, 32'h8000, 32'h47000, 32'd0);
        start(0, 32'h2C0, 32'h1);
        rw(16'h0004, 32'h0);   // run cleared right away
        wait_idle(0); get_status(0);
        ev("run cleared: stopped", rd_val[1], 1'b1);
        rr(16'h0048); ev("run cleared: one descriptor", rd_val, 32'd1);
        check_untouched("run cleared: second descriptor not run", 32'h47000, 64);
        // a chain whose next pointer is zero without the stop bit ends too
        put_desc(32'h2C0, 32'hAD4B0002, 32'd16, 32'h8000, 32'h48000, 32'd0);
        start(0, 32'h2C0, 32'h1); wait_idle(0); get_status(0); ev("next pointer zero stops", rd_val, 32'h00000006);
        stop(0);

        // timing sanity: the burst length never exceeded 16 beats (128 bytes) and the copies used several bursts
        ev("longest burst", max_len, 16);
        ev("no burst crossed a 4 KiB boundary", bad_bursts, 0);
        ev("bursts were issued", (wr_bursts > 20 && rd_bursts > 25), 1);

        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (errors == 0 && checks > 100) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin
        #200000000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
