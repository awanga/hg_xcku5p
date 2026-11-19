// SPDX-License-Identifier: MIT
// Testbench for card_regs and user_regs (the register blocks of the CPU-less PCIe card). Expected values are written out from the register maps in the
// module headers, not read from the RTL. Both DUTs sit behind AXI4-Lite master tasks.
`timescale 1ns/1ps
module tb_card;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    integer checks = 0, errors = 0;

    task chk(input [31:0] got, input [31:0] exp, input [255:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("MISMATCH %0s: got %h expected %h", what, got, exp);
            end
        end
    endtask

    // ------------------------------------------------------------ card_regs
    reg  [11:0] c_aw = 0, c_ar = 0;
    reg  [31:0] c_wd = 0;
    reg  [3:0]  c_ws = 0;
    reg         c_awv = 0, c_wv = 0, c_bready = 0, c_arv = 0, c_rready = 0;
    wire        c_awr, c_wr, c_bv, c_arr, c_rv;
    wire [1:0]  c_br, c_rr;
    wire [31:0] c_rd;
    reg         calib = 0, key = 0;
    wire [7:0]  led;
    card_regs #(.VERSION(32'h00000401), .BUILD(32'hDEADBEEF), .PCI_ID(32'h12345678), .PCI_CLASS(32'h9ABCDEF0), .PCI_SUBSYS(32'h0F1E2D3C),
                .DDR_MIB(32'd2048), .CLK_HZ(32'd50)) dc (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(c_aw), .s_awvalid(c_awv), .s_awready(c_awr), .s_wdata(c_wd), .s_wstrb(c_ws), .s_wvalid(c_wv), .s_wready(c_wr),
        .s_bresp(c_br), .s_bvalid(c_bv), .s_bready(c_bready),
        .s_araddr(c_ar), .s_arvalid(c_arv), .s_arready(c_arr), .s_rdata(c_rd), .s_rresp(c_rr), .s_rvalid(c_rv), .s_rready(c_rready),
        .calib_in(calib), .key_in(key), .led(led));

    task cw(input [11:0] a, input [31:0] d, input [3:0] s);
        begin
            @(negedge clk); c_aw = a; c_wd = d; c_ws = s; c_awv = 1; c_wv = 1; #1;
            while (!c_awr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); c_awv = 0; c_wv = 0; c_bready = 1; #1;
            while (!c_bv) begin @(negedge clk); #1; end
            chk({30'd0, c_br}, 0, "card bresp");
            @(posedge clk); @(negedge clk); c_bready = 0;
        end
    endtask
    reg [31:0] cq;
    task cr(input [11:0] a);
        begin
            @(negedge clk); c_ar = a; c_arv = 1; #1;
            while (!c_arr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); c_arv = 0; c_rready = 1; #1;
            while (!c_rv) begin @(negedge clk); #1; end
            cq = c_rd;
            chk({30'd0, c_rr}, 0, "card rresp");
            @(posedge clk); @(negedge clk); c_rready = 0;
        end
    endtask

    // ------------------------------------------------------------ user_ip (placeholder window: reads 0, writes ignored, always OKAY)
    reg  [13:0] i_aw = 0, i_ar = 0;
    reg  [31:0] i_wd = 0;
    reg         i_awv = 0, i_wv = 0, i_bready = 0, i_arv = 0, i_rready = 0;
    wire        i_awr, i_wr, i_bv, i_arr, i_rv;
    wire [1:0]  i_br, i_rr;
    wire [31:0] i_rd;
    user_ip di (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(i_aw), .s_awvalid(i_awv), .s_awready(i_awr), .s_wdata(i_wd), .s_wstrb(4'hF), .s_wvalid(i_wv), .s_wready(i_wr),
        .s_bresp(i_br), .s_bvalid(i_bv), .s_bready(i_bready),
        .s_araddr(i_ar), .s_arvalid(i_arv), .s_arready(i_arr), .s_rdata(i_rd), .s_rresp(i_rr), .s_rvalid(i_rv), .s_rready(i_rready));
    task iw(input [13:0] a, input [31:0] d);
        begin
            @(negedge clk); i_aw = a; i_wd = d; i_awv = 1; i_wv = 1; #1;
            while (!i_awr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); i_awv = 0; i_wv = 0; i_bready = 1; #1;
            while (!i_bv) begin @(negedge clk); #1; end
            chk({30'd0, i_br}, 0, "ip bresp");
            @(posedge clk); @(negedge clk); i_bready = 0;
        end
    endtask
    reg [31:0] iq;
    task ir(input [13:0] a);
        begin
            @(negedge clk); i_ar = a; i_arv = 1; #1;
            while (!i_arr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); i_arv = 0; i_rready = 1; #1;
            while (!i_rv) begin @(negedge clk); #1; end
            iq = i_rd;
            chk({30'd0, i_rr}, 0, "ip rresp");
            @(posedge clk); @(negedge clk); i_rready = 0;
        end
    endtask

    // ------------------------------------------------------------ user_regs
    reg  [11:0] u_aw = 0, u_ar = 0;
    reg  [31:0] u_wd = 0;
    reg  [3:0]  u_ws = 0;
    reg         u_awv = 0, u_wv = 0, u_bready = 0, u_arv = 0, u_rready = 0;
    wire        u_awr, u_wr, u_bv, u_arr, u_rv;
    wire [1:0]  u_br, u_rr;
    wire [31:0] u_rd;
    wire [511:0] ctl;
    reg  [511:0] sts;
    wire [31:0] kick;
    reg  [31:0] ev = 0;
    wire        uirq;
    user_regs du (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(u_aw), .s_awvalid(u_awv), .s_awready(u_awr), .s_wdata(u_wd), .s_wstrb(u_ws), .s_wvalid(u_wv), .s_wready(u_wr),
        .s_bresp(u_br), .s_bvalid(u_bv), .s_bready(u_bready),
        .s_araddr(u_ar), .s_arvalid(u_arv), .s_arready(u_arr), .s_rdata(u_rd), .s_rresp(u_rr), .s_rvalid(u_rv), .s_rready(u_rready),
        .ctl(ctl), .sts(sts), .kick(kick), .event_in(ev), .irq(uirq));

    task uw(input [11:0] a, input [31:0] d, input [3:0] s);
        begin
            @(negedge clk); u_aw = a; u_wd = d; u_ws = s; u_awv = 1; u_wv = 1; #1;
            while (!u_awr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); u_awv = 0; u_wv = 0; u_bready = 1; #1;
            while (!u_bv) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); u_bready = 0;
        end
    endtask
    reg [31:0] uq;
    task ur(input [11:0] a);
        begin
            @(negedge clk); u_ar = a; u_arv = 1; #1;
            while (!u_arr) begin @(negedge clk); #1; end
            @(posedge clk); @(negedge clk); u_arv = 0; u_rready = 1; #1;
            while (!u_rv) begin @(negedge clk); #1; end
            uq = u_rd;
            @(posedge clk); @(negedge clk); u_rready = 0;
        end
    endtask

    // kick pulse recorder: the number of clocks each kick bit was high
    integer kick_hi = 0, kick_pulses = 0;
    reg [31:0] kick_or = 0;
    always @(posedge clk) begin
        if (kick != 0) begin kick_hi = kick_hi + 1; kick_or = kick_or | kick; end
        if (kick != 0 && kick_hi == 1) kick_pulses = kick_pulses + 1;
        if (kick == 0) kick_hi = 0;
    end

    // exact seconds period: cycles between increments of the uptime counter (CLK_HZ = 50), watched inside the DUT
    integer cyc = 0, last_inc = -1, periods = 0, bad_periods = 0;
    reg [31:0] sec_prev = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        sec_prev <= dc.sec;
        if (dc.sec != sec_prev && dc.sec != 0) begin
            if (last_inc >= 0) begin
                periods = periods + 1;
                if (cyc - last_inc != 50) bad_periods = bad_periods + 1;
            end
            last_inc = cyc;
        end
    end

    integer i, t0, t1;
    initial begin
        sts = 512'd0;
        for (i = 0; i < 16; i = i + 1) sts[32*i +: 32] = 32'hA5000000 + 32'h00010001 * i;
        repeat (4) @(negedge clk);
        rst_n = 1;
        t0 = $time / 10;
        // ---- card_regs
        cr(12'h000); chk(cq, 32'h43415244, "ID");
        cr(12'h004); chk(cq, 1, "LAYOUT");
        cr(12'h008); chk(cq, 32'h00000401, "VERSION");
        cr(12'h00C); chk(cq, 32'hDEADBEEF, "BUILD");
        cr(12'h010); chk(cq, 32'h12345678, "PCI_ID");
        cr(12'h014); chk(cq, 32'h9ABCDEF0, "PCI_CLASS");
        cr(12'h018); chk(cq, 32'h0F1E2D3C, "PCI_SUBSYS");
        cr(12'h01C); chk(cq, 32'h0000000F, "CAPS");
        cr(12'h024); chk(cq, 2048, "DDR_MIB");
        cr(12'h020); chk(cq, 0, "STATUS before calib");
        calib = 1; repeat (4) @(negedge clk);
        cr(12'h020); chk(cq, 1, "STATUS calib");
        key = 1; repeat (4) @(negedge clk);
        cr(12'h020); chk(cq, 3, "STATUS calib+key");
        calib = 0; repeat (4) @(negedge clk);
        cr(12'h020); chk(cq, 2, "STATUS key only");
        // read-only words ignore writes
        cw(12'h000, 32'hFFFFFFFF, 4'hF); cr(12'h000); chk(cq, 32'h43415244, "ID after write");
        cw(12'h024, 32'h0, 4'hF); cr(12'h024); chk(cq, 2048, "DDR_MIB after write");
        cw(12'h010, 32'h0, 4'hF); cr(12'h010); chk(cq, 32'h12345678, "PCI_ID after write");
        // scratch with byte strobes
        cr(12'h02C); chk(cq, 0, "SCRATCH reset");
        cw(12'h02C, 32'h11223344, 4'hF); cr(12'h02C); chk(cq, 32'h11223344, "SCRATCH full");
        cw(12'h02C, 32'hAABBCCDD, 4'b0101); cr(12'h02C); chk(cq, 32'h11BB33DD, "SCRATCH strobes 0101");
        cw(12'h02C, 32'h99999999, 4'b0000); cr(12'h02C); chk(cq, 32'h11BB33DD, "SCRATCH strobes 0");
        // LED
        chk({24'd0, led}, 0, "led reset");
        cw(12'h030, 32'hFFFFFFA5, 4'hF); cr(12'h030); chk(cq, 32'h000000A5, "LED read");
        chk({24'd0, led}, 32'hA5, "led pins");
        cw(12'h030, 32'h0000005A, 4'b0010); chk({24'd0, led}, 32'hA5, "led byte 1 strobe ignored");
        // unlisted words
        cr(12'h034); chk(cq, 0, "unlisted 0x34");
        cr(12'h040); chk(cq, 0, "unlisted 0x40");
        cr(12'hFFC); chk(cq, 0, "unlisted 0xFFC");
        // uptime: seconds = elapsed cycles / 50 since reset release (+-1 for the bus latency)
        repeat (160) @(negedge clk);
        cr(12'h028); t1 = $time / 10;
        checks = checks + 1;
        if (cq < ((t1 - t0) / 50) - 1 || cq > ((t1 - t0) / 50) + 1 || cq < 3) begin
            errors = errors + 1; $display("MISMATCH UPTIME got %0d, elapsed %0d cycles", cq, t1 - t0);
        end
        repeat (200) @(negedge clk);
        chk(periods >= 3, 1, "uptime periods observed");
        chk(bad_periods, 0, "uptime period is CLK_HZ cycles");
        // reset clears scratch, LED and the uptime
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;
        cr(12'h02C); chk(cq, 0, "SCRATCH after reset");
        cr(12'h030); chk(cq, 0, "LED after reset");
        chk({24'd0, led}, 0, "led pins after reset");
        cr(12'h028); chk(cq, 0, "UPTIME after reset");

        // ---- user_regs
        for (i = 0; i < 16; i = i + 1) begin ur(4 * i); chk(uq, 0, "CTL reset"); end
        for (i = 0; i < 16; i = i + 1) uw(4 * i, 32'hC0DE0000 + i, 4'hF);
        for (i = 0; i < 16; i = i + 1) begin ur(4 * i); chk(uq, 32'hC0DE0000 + i, "CTL read"); end
        for (i = 0; i < 16; i = i + 1) chk(ctl[32*i +: 32], 32'hC0DE0000 + i, "ctl bus");
        uw(12'h008, 32'hFFFF0000, 4'b1100); ur(12'h008); chk(uq, 32'hFFFF0002, "CTL strobes");
        chk(ctl[32*2 +: 32], 32'hFFFF0002, "ctl bus strobes");
        for (i = 0; i < 16; i = i + 1) begin ur(12'h040 + 4 * i); chk(uq, 32'hA5000000 + 32'h00010001 * i, "STS read"); end
        uw(12'h040, 32'h0, 4'hF); ur(12'h040); chk(uq, 32'hA5000000, "STS ignores writes");
        ur(12'h000); chk(uq, 32'hC0DE0000, "write to STS word 0 does not reach CTL[0]");
        uw(12'h044, 32'h0, 4'hF); ur(12'h004); chk(uq, 32'hC0DE0001, "write to STS word 1 does not reach CTL[1]");
        sts[32*5 +: 32] = 32'h0BADF00D; ur(12'h054); chk(uq, 32'h0BADF00D, "STS follows input");
        ur(12'h08C); chk(uq, 32'h00010000, "layout");
        ur(12'h090); chk(uq, 0, "unlisted 0x90");
        ur(12'h0C0); chk(uq, 0, "unlisted 0xC0");
        ur(12'hFFC); chk(uq, 0, "unlisted 0xFFC");
        // KICK: one clock per written bit, one pulse per write, reads 0, partial strobe ignored
        kick_pulses = 0; kick_or = 0;
        uw(12'h080, 32'h80000011, 4'hF);
        repeat (4) @(negedge clk);
        chk(kick_pulses, 1, "kick pulse count");
        chk(kick_or, 32'h80000011, "kick bits");
        chk(kick_hi, 0, "kick low after pulse");
        ur(12'h080); chk(uq, 0, "KICK reads 0");
        kick_or = 0; uw(12'h080, 32'hFFFFFFFF, 4'b0111); repeat (4) @(negedge clk);
        chk(kick_or, 0, "kick partial strobe ignored");
        // events: set by pulse, W1C, set wins over clear, mask for irq
        chk({31'd0, uirq}, 0, "irq idle");
        @(negedge clk); ev = 32'h00000006; @(negedge clk); ev = 0; @(negedge clk);
        ur(12'h084); chk(uq, 6, "EVENT set");
        chk({31'd0, uirq}, 0, "irq masked");
        uw(12'h088, 32'h00000004, 4'hF); ur(12'h088); chk(uq, 4, "IEN");
        @(negedge clk); chk({31'd0, uirq}, 1, "irq enabled");
        uw(12'h084, 32'h00000002, 4'hF); ur(12'h084); chk(uq, 4, "EVENT W1C bit 1 only");
        chk({31'd0, uirq}, 1, "irq still");
        uw(12'h084, 32'h00000004, 4'hF); ur(12'h084); chk(uq, 0, "EVENT W1C bit 2");
        chk({31'd0, uirq}, 0, "irq cleared");
        uw(12'h084, 32'hFFFFFFFF, 4'hF);
        ur(12'h084); chk(uq, 0, "EVENT cleared");
        // reset clears CTL, events and IEN
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;
        ur(12'h008); chk(uq, 0, "CTL after reset");
        ur(12'h088); chk(uq, 0, "IEN after reset");

        // user_ip: reads 0 over the whole 16 KiB window, writes are ignored (also the first and last word), responses OKAY
        ir(14'h0000); chk(iq, 0, "ip word 0");
        iw(14'h0000, 32'hFFFFFFFF); ir(14'h0000); chk(iq, 0, "ip word 0 after write");
        iw(14'h3FFC, 32'h12345678); ir(14'h3FFC); chk(iq, 0, "ip last word after write");
        iw(14'h0010, 32'hA5A5A5A5); ir(14'h0010); chk(iq, 0, "ip word 4 after write");

        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (checks > 0 && errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin
        #2000000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
