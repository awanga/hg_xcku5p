// SPDX-License-Identifier: MIT
// Testbench for user_ip and mem_probe (self-test master on each user DDR4 port) with AXI4 slave models that also check the master's protocol use.
// Expected values come from the register maps in the module headers and from the pattern definition (beat k lane j = SEED + 8k + j), computed here independently.
`timescale 1ns/1ps
module tb_mem #(parameter [3:0] SEEDBITS = 4'd1) (
    input  wire         clk,
    input  wire [31:0]  err_wr, input wire [31:0] flip_rd,   // start address of a write burst answered SLVERR; address of a read beat with bit 0 flipped
    input  wire [31:0]  awaddr, input wire [7:0] awlen, input wire awvalid, output wire awready,
    input  wire [255:0] wdata, input wire wlast, input wire wvalid, output wire wready,
    output reg  [1:0]   bresp, output reg bvalid, input wire bready,
    input  wire [31:0]  araddr, input wire [7:0] arlen, input wire arvalid, output wire arready,
    output reg  [255:0] rdata, output reg [1:0] rresp, output reg rlast, output reg rvalid, input wire rready,
    output reg  [31:0]  bad,       // protocol violations seen
    output reg  [31:0]  n_aw, n_ar, beats_w, beats_r
);
    reg [255:0] mem [0:8191];
    reg [31:0] lf = {28'd0, SEEDBITS} | 32'h1357;
    always @(posedge clk) lf <= {lf[30:0], lf[31] ^ lf[21] ^ lf[1] ^ lf[0]};
    reg [31:0] a_w, a_r;
    reg [7:0] l_w, l_r;
    reg wph, rph;
    reg [31:0] bw, br;
    reg awseen;
    assign awready = !wph && !bvalid && lf[3];
    assign wready = wph && lf[5];
    assign arready = !rph && lf[7];
    integer i;
    initial begin
        bad = 0; n_aw = 0; n_ar = 0; beats_w = 0; beats_r = 0; wph = 0; rph = 0; bvalid = 0; rvalid = 0; rlast = 0; rresp = 0; bresp = 0; rdata = 0;
        for (i = 0; i < 8192; i = i + 1) mem[i] = 256'd0;
    end
    always @(posedge clk) begin
        if (awvalid && awready) begin
            a_w <= awaddr; l_w <= awlen; wph <= 1; bw <= 0; n_aw <= n_aw + 1;
            if (awlen > 8'd15) bad <= bad + 1;
            if (((awaddr & 32'hFFF) + (awlen + 1) * 32) > 32'd4096) bad <= bad + 1;
            if (awaddr[4:0] != 0) bad <= bad + 1;
        end
        if (wvalid && wready) begin
            mem[(a_w >> 5) & 8191] <= wdata;
            a_w <= a_w + 32; bw <= bw + 1; beats_w <= beats_w + 1;
            if (wlast != (bw == l_w)) bad <= bad + 1;
            if (wlast) begin wph <= 0; bvalid <= 1; bresp <= (a_w - l_w * 32 == err_wr) ? 2'b10 : 2'b00; end
        end
        if (bvalid && bready) bvalid <= 0;
        if (arvalid && arready) begin
            a_r <= araddr; l_r <= arlen; rph <= 1; br <= 0; n_ar <= n_ar + 1;
            if (arlen > 8'd15) bad <= bad + 1;
            if (((araddr & 32'hFFF) + (arlen + 1) * 32) > 32'd4096) bad <= bad + 1;
        end
        if (rph && (!rvalid || rready) && lf[9]) begin
            rvalid <= 1; rdata <= mem[(a_r >> 5) & 8191] ^ ((a_r == flip_rd) ? 256'd1 : 256'd0); rresp <= 0;
            rlast <= (br == l_r);
            a_r <= a_r + 32; br <= br + 1;
            if (br == l_r) rph <= 0;
        end else if (rvalid && rready) begin
            rvalid <= 0; rlast <= 0;
        end
        if (rvalid && rready) beats_r <= beats_r + 1;
    end
endmodule

module tb_uip;
    reg clk = 0, mclk = 0, rst_n = 0;
    always #5 clk = ~clk;       // 100 MHz register clock
    always #1.5 mclk = ~mclk;   // 333 MHz memory clock
    integer checks = 0, errors = 0;
    task chk(input [31:0] got, input [31:0] exp, input [255:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin errors = errors + 1; $display("MISMATCH %0s: got %h expected %h", what, got, exp); end
        end
    endtask

    reg  [13:0] aw = 0, ar = 0;
    reg  [31:0] wd = 0;
    reg  [3:0]  ws = 4'hF;
    reg         awv = 0, wv = 0, bready = 0, arv = 0, rready = 0;
    wire        awr, wr, bv, arr, rv;
    wire [1:0]  br, rr;
    wire [31:0] rd;
    wire [2:0]  irq;
    reg  [2:0]  pend = 0, seen = 0;
    wire [63:0] maw; wire [15:0] mawlen; wire [5:0] mawsize; wire [3:0] mawburst; wire [7:0] mawid; wire [1:0] mawv, mawr;
    wire [511:0] mwd; wire [63:0] mws; wire [1:0] mwl, mwv, mwr;
    wire [7:0] mbid = 8'd0; wire [3:0] mbresp; wire [1:0] mbv, mbr;
    wire [63:0] mar; wire [15:0] marlen; wire [5:0] marsize; wire [3:0] marburst; wire [7:0] marid; wire [1:0] marv, marr;
    wire [511:0] mrd; wire [3:0] mrresp; wire [1:0] mrl, mrv, mrr;
    wire [7:0] mrid = 8'd0;
    user_ip #(.UMEM(2), .UIRQ(3)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(aw), .s_awvalid(awv), .s_awready(awr), .s_wdata(wd), .s_wstrb(ws), .s_wvalid(wv), .s_wready(wr),
        .s_bresp(br), .s_bvalid(bv), .s_bready(bready),
        .s_araddr(ar), .s_arvalid(arv), .s_arready(arr), .s_rdata(rd), .s_rresp(rr), .s_rvalid(rv), .s_rready(rready),
        .irq(irq), .irq_pend(pend), .irq_seen(seen), .mclk(mclk), .mrst_n(rst_n),
        .m_awaddr(maw), .m_awlen(mawlen), .m_awsize(mawsize), .m_awburst(mawburst), .m_awid(mawid), .m_awvalid(mawv), .m_awready(mawr),
        .m_wdata(mwd), .m_wstrb(mws), .m_wlast(mwl), .m_wvalid(mwv), .m_wready(mwr),
        .m_bid(mbid), .m_bresp(mbresp), .m_bvalid(mbv), .m_bready(mbr),
        .m_araddr(mar), .m_arlen(marlen), .m_arsize(marsize), .m_arburst(marburst), .m_arid(marid), .m_arvalid(marv), .m_arready(marr),
        .m_rid(mrid), .m_rdata(mrd), .m_rresp(mrresp), .m_rlast(mrl), .m_rvalid(mrv), .m_rready(mrr));

    wire [31:0] bad0, bad1, naw0, naw1, nar0, nar1, bw0, bw1, brd0, brd1;
    // port 0: a write response error for the burst at 0x4000, a flipped bit in the read at 0x4220; port 1: clean
    reg [31:0] err0 = 32'hFFFFFFFF, flip0 = 32'hFFFFFFFF;
    tb_mem #(.SEEDBITS(4'd1)) m0 (.clk(mclk), .err_wr(err0), .flip_rd(flip0),
        .awaddr(maw[31:0]), .awlen(mawlen[7:0]), .awvalid(mawv[0]), .awready(mawr[0]),
        .wdata(mwd[255:0]), .wlast(mwl[0]), .wvalid(mwv[0]), .wready(mwr[0]), .bresp(mbresp[1:0]), .bvalid(mbv[0]), .bready(mbr[0]),
        .araddr(mar[31:0]), .arlen(marlen[7:0]), .arvalid(marv[0]), .arready(marr[0]),
        .rdata(mrd[255:0]), .rresp(mrresp[1:0]), .rlast(mrl[0]), .rvalid(mrv[0]), .rready(mrr[0]),
        .bad(bad0), .n_aw(naw0), .n_ar(nar0), .beats_w(bw0), .beats_r(brd0));
    tb_mem #(.SEEDBITS(4'd5)) m1 (.clk(mclk), .err_wr(32'hFFFFFFFF), .flip_rd(32'hFFFFFFFF),
        .awaddr(maw[63:32]), .awlen(mawlen[15:8]), .awvalid(mawv[1]), .awready(mawr[1]),
        .wdata(mwd[511:256]), .wlast(mwl[1]), .wvalid(mwv[1]), .wready(mwr[1]), .bresp(mbresp[3:2]), .bvalid(mbv[1]), .bready(mbr[1]),
        .araddr(mar[63:32]), .arlen(marlen[15:8]), .arvalid(marv[1]), .arready(marr[1]),
        .rdata(mrd[511:256]), .rresp(mrresp[3:2]), .rlast(mrl[1]), .rvalid(mrv[1]), .rready(mrr[1]),
        .bad(bad1), .n_aw(naw1), .n_ar(nar1), .beats_w(bw1), .beats_r(brd1));

    task w(input [13:0] a, input [31:0] d);
        begin
            @(negedge clk); aw = a; wd = d; awv = 1; wv = 1; #1;
            while (!awr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); awv = 0; wv = 0; bready = 1; #1;
            while (!bv) begin @(negedge clk); #1; end
            chk({30'd0, br}, 0, "bresp");
            @(posedge clk); @(negedge clk); bready = 0;
        end
    endtask
    reg [31:0] q;
    task r(input [13:0] a);
        begin
            @(negedge clk); ar = a; arv = 1; #1;
            while (!arr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); arv = 0; rready = 1; #1;
            while (!rv) begin @(negedge clk); #1; end
            q = rd;
            chk({30'd0, rr}, 0, "rresp");
            @(posedge clk); @(negedge clk); rready = 0;
        end
    endtask
    task wait_done(input [13:0] st);
        integer n;
        begin
            n = 0; q = 0;
            while (!(q & 2) && n < 2000) begin r(st); n = n + 1; end
            chk(n < 2000, 1, "run finishes");
        end
    endtask

    // independent pattern model
    function [31:0] pat(input [31:0] seed, input integer k, input integer j);
        pat = seed + 8 * k + j;
    endfunction
    integer k, j, bad_words;
    task check_mem0(input [31:0] base, input [31:0] seed, input integer beats);
        begin
            bad_words = 0;
            for (k = 0; k < beats; k = k + 1)
                for (j = 0; j < 8; j = j + 1)
                    if (m0.mem[((base >> 5) + k) & 8191][32*j +: 32] !== pat(seed, k, j)) bad_words = bad_words + 1;
            chk(bad_words, 0, "memory 0 pattern");
        end
    endtask
    task check_mem1(input [31:0] base, input [31:0] seed, input integer beats);
        begin
            bad_words = 0;
            for (k = 0; k < beats; k = k + 1)
                for (j = 0; j < 8; j = j + 1)
                    if (m1.mem[((base >> 5) + k) & 8191][32*j +: 32] !== pat(seed, k, j)) bad_words = bad_words + 1;
            chk(bad_words, 0, "memory 1 pattern");
        end
    endtask

    localparam [13:0] P0 = 14'h100, P1 = 14'h140;
    integer cyc_w, cyc_r;
    initial begin
        repeat (6) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);
        // identification and capabilities
        r(14'h000); chk(q, 32'h55495031, "ID");
        r(14'h004); chk(q, {16'h0001, 8'd3, 8'd2}, "CAPS");
        // interrupt lines
        r(14'h008); chk(q, 0, "IRQ_SET reset"); chk(irq, 0, "irq reset");
        w(14'h008, 32'h5); r(14'h008); chk(q, 5, "IRQ_SET"); chk(irq, 3'b101, "irq lines");
        ws = 4'b0011; w(14'h008, 32'h7); ws = 4'hF; chk(irq, 3'b101, "IRQ_SET needs a word write");
        pend = 3'b010; r(14'h00C); chk(q, 2, "IRQ_PEND"); pend = 0;
        seen = 3'b101; r(14'h010); chk(q, 5, "IRQ_SEEN"); r(14'h00C); chk(q, 0, "IRQ_SEEN is not IRQ_PEND"); seen = 0;
        w(14'h008, 0); chk(irq, 0, "irq cleared");
        w(14'h008, 32'hFFFFFFF8); r(14'h008); chk(q, 0, "IRQ_SET bits above UIRQ");
        // registers of probe 0
        w(P0 + 14'h08, 32'h000041FF); r(P0 + 14'h08); chk(q, 32'h00004000, "BASE low bits read 0");
        w(P0 + 14'h0C, 0); r(P0 + 14'h0C); chk(q, 1, "BEATS 0 reads 1");
        // run 1: port 0, 40 beats = bursts of 16, 16, 8 at 0x4000
        w(P0 + 14'h08, 32'h4000); w(P0 + 14'h0C, 40); w(P0 + 14'h10, 32'h12340000);
        r(P0 + 14'h04); chk(q, 0, "STATUS idle");
        w(P0, 1);
        wait_done(P0 + 14'h04);
        chk(q, 32'h2, "STATUS done, no error");
        r(P0 + 14'h14); chk(q, 0, "MISMATCH 0");
        r(P0 + 14'h18); cyc_w = q; chk(cyc_w >= 40 && cyc_w < 2000, 1, "WR_CYCLES plausible");
        r(P0 + 14'h1C); cyc_r = q; chk(cyc_r >= 40 && cyc_r < 2000, 1, "RD_CYCLES plausible");
        check_mem0(32'h4000, 32'h12340000, 40);
        chk(naw0, 3, "bursts written"); chk(nar0, 3, "bursts read"); chk(bw0, 40, "beats written"); chk(brd0, 40, "beats read");
        chk(bad0, 0, "port 0 protocol");
        chk(maw[31:0] >= 32'h4000 && maw[31:0] <= 32'h4400, 1, "port 0 address range");
        // start while done is shown, clear, and a second run on the same port
        w(P0, 2); r(P0 + 14'h04); chk(q, 0, "clear DONE"); r(P0 + 14'h18); chk(q, 0, "clear counters");
        // both ports at once with different bases, seeds and lengths (1 beat; 17 beats = 16 + 1)
        w(P0 + 14'h08, 32'h8000); w(P0 + 14'h0C, 1); w(P0 + 14'h10, 32'hFFFFFFFC);
        w(P1 + 14'h08, 32'h2000); w(P1 + 14'h0C, 17); w(P1 + 14'h10, 32'h00000777);
        w(P0, 1); w(P1, 1);
        wait_done(P0 + 14'h04); wait_done(P1 + 14'h04);
        r(P0 + 14'h04); chk(q, 2, "port 0 status"); r(P1 + 14'h04); chk(q, 2, "port 1 status");
        r(P0 + 14'h14); chk(q, 0, "port 0 mismatches"); r(P1 + 14'h14); chk(q, 0, "port 1 mismatches");
        check_mem0(32'h8000, 32'hFFFFFFFC, 1);   // the seed wraps at 2^32
        check_mem1(32'h2000, 32'h00000777, 17);
        chk(bad0, 0, "port 0 protocol after run 2"); chk(bad1, 0, "port 1 protocol");
        chk(naw1, 2, "port 1 bursts 16+1"); chk(bw1, 17, "port 1 beats");
        // START starts the selected ports in the same clock: both at once, a bit above the ports ignored, and a byte write does nothing
        w(P0 + 14'h08, 32'h6000); w(P0 + 14'h0C, 33); w(P0 + 14'h10, 32'h51);
        w(P1 + 14'h08, 32'h3000); w(P1 + 14'h0C, 20); w(P1 + 14'h10, 32'h52);
        w(P0, 2); w(P1, 2);
        ws = 4'b0001; w(14'h014, 32'h3); ws = 4'hF;
        repeat (30) @(negedge clk); r(P0 + 14'h04); chk(q, 0, "START needs a word write (port 0)");
        w(14'h014, 32'hFFFFFFFC); repeat (30) @(negedge clk); r(P0 + 14'h04); chk(q, 0, "START bits above the ports (port 0)");
        w(14'h014, 32'h3);
        wait_done(P0 + 14'h04); wait_done(P1 + 14'h04);
        r(P0 + 14'h04); chk(q, 2, "START: port 0 done"); r(P1 + 14'h04); chk(q, 2, "START: port 1 done");
        check_mem0(32'h6000, 32'h51, 33); check_mem1(32'h3000, 32'h52, 20);
        w(P0, 2); w(P1, 2);
        // a start request while busy is ignored: two starts in a row make one run
        w(P1 + 14'h10, 32'h1); w(P1 + 14'h0C, 16);
        w(P1, 1); w(P1, 1);
        wait_done(P1 + 14'h04); repeat (40) @(negedge clk);
        chk(naw1, 5, "second start ignored while busy");
        // a corrupted read beat (beat 3 of 40 at 0x4000) is counted once; the write data is intact
        flip0 = 32'h4000 + 3 * 32;
        w(P0, 2); w(P0 + 14'h08, 32'h4000); w(P0 + 14'h0C, 40); w(P0 + 14'h10, 32'h12340000);
        w(P0, 1); wait_done(P0 + 14'h04);
        chk(q, 2, "flipped bit: done, no error"); r(P0 + 14'h14); chk(q, 1, "MISMATCH counts the flipped beat");
        // a corrupted last beat is counted before DONE is shown
        flip0 = 32'h4000 + 39 * 32;
        w(P0, 2); w(P0, 1); wait_done(P0 + 14'h04);
        r(P0 + 14'h14); chk(q, 1, "MISMATCH counts a flipped last beat before DONE");
        flip0 = 32'hFFFFFFFF;
        // a non-OKAY write response (second burst) sets ERR and nothing else
        err0 = 32'h4000 + 512;
        w(P0, 2); w(P0, 1); wait_done(P0 + 14'h04);
        chk(q, 32'h6, "SLVERR: done and error"); r(P0 + 14'h14); chk(q, 0, "SLVERR: no mismatch");
        err0 = 32'hFFFFFFFF;
        w(P0, 2); r(P0 + 14'h04); chk(q, 0, "clear removes ERR and DONE");
        // reset returns the registers to idle
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);
        r(P0 + 14'h0C); chk(q, 1, "BEATS after reset"); r(P0 + 14'h08); chk(q, 0, "BASE after reset"); r(P0 + 14'h04); chk(q, 0, "STATUS after reset");
        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (checks > 0 && errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin #4000000; $display("TBRESULT watchdog FAIL"); $finish; end
endmodule
