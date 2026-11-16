// SPDX-License-Identifier: MIT
// vpcie_ep end to end: a host-bridge master enumerates 00:00.0 through the ECAM window, programs BAR0 and BAR1, and drives an H2C and a C2H transfer through the
// XDMA-compatible registers in BAR1 while the CPU side (pcie_regs window) opens the card window. vdma_cc is the Vivado clock converter IP; here a wire stub (one clock).
// Expected values come from the register maps and the byte pattern, not from the DUT.
`timescale 1ns / 1ps
module vdma_cc (
    input  wire        s_axi_aclk, s_axi_aresetn,
    input  wire [3:0]  s_axi_awid, input wire [31:0] s_axi_awaddr, input wire [7:0] s_axi_awlen, input wire [2:0] s_axi_awsize, input wire [1:0] s_axi_awburst,
    input  wire        s_axi_awlock, input wire [3:0] s_axi_awcache, input wire [2:0] s_axi_awprot, input wire [3:0] s_axi_awregion, input wire [3:0] s_axi_awqos,
    input  wire        s_axi_awvalid, output wire s_axi_awready,
    input  wire [63:0] s_axi_wdata, input wire [7:0] s_axi_wstrb, input wire s_axi_wlast, input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [3:0]  s_axi_bid, output wire [1:0] s_axi_bresp, output wire s_axi_bvalid, input wire s_axi_bready,
    input  wire [3:0]  s_axi_arid, input wire [31:0] s_axi_araddr, input wire [7:0] s_axi_arlen, input wire [2:0] s_axi_arsize, input wire [1:0] s_axi_arburst,
    input  wire        s_axi_arlock, input wire [3:0] s_axi_arcache, input wire [2:0] s_axi_arprot, input wire [3:0] s_axi_arregion, input wire [3:0] s_axi_arqos,
    input  wire        s_axi_arvalid, output wire s_axi_arready,
    output wire [3:0]  s_axi_rid, output wire [63:0] s_axi_rdata, output wire [1:0] s_axi_rresp, output wire s_axi_rlast, output wire s_axi_rvalid, input wire s_axi_rready,
    input  wire        m_axi_aclk, m_axi_aresetn,
    output wire [3:0]  m_axi_awid, output wire [31:0] m_axi_awaddr, output wire [7:0] m_axi_awlen, output wire [2:0] m_axi_awsize, output wire [1:0] m_axi_awburst,
    output wire        m_axi_awlock, output wire [3:0] m_axi_awcache, output wire [2:0] m_axi_awprot, output wire [3:0] m_axi_awregion, output wire [3:0] m_axi_awqos,
    output wire        m_axi_awvalid, input wire m_axi_awready,
    output wire [63:0] m_axi_wdata, output wire [7:0] m_axi_wstrb, output wire m_axi_wlast, output wire m_axi_wvalid, input wire m_axi_wready,
    input  wire [3:0]  m_axi_bid, input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready,
    output wire [3:0]  m_axi_arid, output wire [31:0] m_axi_araddr, output wire [7:0] m_axi_arlen, output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst,
    output wire        m_axi_arlock, output wire [3:0] m_axi_arcache, output wire [2:0] m_axi_arprot, output wire [3:0] m_axi_arregion, output wire [3:0] m_axi_arqos,
    output wire        m_axi_arvalid, input wire m_axi_arready,
    input  wire [3:0]  m_axi_rid, input wire [63:0] m_axi_rdata, input wire [1:0] m_axi_rresp, input wire m_axi_rlast, input wire m_axi_rvalid, output wire m_axi_rready
);
    assign m_axi_awid = s_axi_awid; assign m_axi_awaddr = s_axi_awaddr; assign m_axi_awlen = s_axi_awlen; assign m_axi_awsize = s_axi_awsize;
    assign m_axi_awburst = s_axi_awburst; assign m_axi_awlock = s_axi_awlock; assign m_axi_awcache = s_axi_awcache; assign m_axi_awprot = s_axi_awprot;
    assign m_axi_awregion = s_axi_awregion; assign m_axi_awqos = s_axi_awqos; assign m_axi_awvalid = s_axi_awvalid; assign s_axi_awready = m_axi_awready;
    assign m_axi_wdata = s_axi_wdata; assign m_axi_wstrb = s_axi_wstrb; assign m_axi_wlast = s_axi_wlast; assign m_axi_wvalid = s_axi_wvalid; assign s_axi_wready = m_axi_wready;
    assign s_axi_bid = m_axi_bid; assign s_axi_bresp = m_axi_bresp; assign s_axi_bvalid = m_axi_bvalid; assign m_axi_bready = s_axi_bready;
    assign m_axi_arid = s_axi_arid; assign m_axi_araddr = s_axi_araddr; assign m_axi_arlen = s_axi_arlen; assign m_axi_arsize = s_axi_arsize;
    assign m_axi_arburst = s_axi_arburst; assign m_axi_arlock = s_axi_arlock; assign m_axi_arcache = s_axi_arcache; assign m_axi_arprot = s_axi_arprot;
    assign m_axi_arregion = s_axi_arregion; assign m_axi_arqos = s_axi_arqos; assign m_axi_arvalid = s_axi_arvalid; assign s_axi_arready = m_axi_arready;
    assign s_axi_rid = m_axi_rid; assign s_axi_rdata = m_axi_rdata; assign s_axi_rresp = m_axi_rresp; assign s_axi_rlast = m_axi_rlast;
    assign s_axi_rvalid = m_axi_rvalid; assign m_axi_rready = s_axi_rready;
endmodule

module tb_vpcie_dma;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    reg  [20:0] s_awaddr = 21'd0, s_araddr = 21'd0;
    reg  [31:0] s_wdata = 32'd0;
    reg         s_awvalid = 1'b0, s_wvalid = 1'b0, s_arvalid = 1'b0, s_bready = 1'b0, s_rready = 1'b0;
    wire        s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [31:0] s_rdata;
    reg  [6:0]  c_awaddr = 7'd0, c_araddr = 7'd0;
    reg  [31:0] c_wdata = 32'd0;
    reg         c_awvalid = 1'b0, c_wvalid = 1'b0, c_arvalid = 1'b0;
    wire        c_awready, c_wready, c_bvalid, c_arready, c_rvalid;
    wire [31:0] c_rdata;
    wire        irq, intx;
    wire [31:0] m_awaddr, m_araddr;
    wire [7:0]  m_awlen, m_arlen, m_wstrb;
    wire [63:0] m_wdata;
    reg  [63:0] m_rdata = 64'd0;
    wire [3:0]  m_awid, m_arid;
    wire [2:0]  m_awsize, m_arsize;
    wire [1:0]  m_awburst, m_arburst;
    wire        m_awvalid, m_wlast, m_wvalid, m_bready, m_arvalid, m_rready;
    reg         m_awready = 1'b0, m_wready = 1'b0, m_bvalid = 1'b0, m_arready = 1'b0, m_rlast = 1'b0, m_rvalid = 1'b0;

    vpcie_ep dut (.clk(clk), .rst_n(rst_n), .cclk(clk), .crst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(4'hF), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bresp(), .s_bvalid(s_bvalid), .s_bready(s_bready), .s_araddr(s_araddr), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .c_awaddr(c_awaddr), .c_awvalid(c_awvalid), .c_awready(c_awready), .c_wdata(c_wdata), .c_wstrb(4'hF), .c_wvalid(c_wvalid),
        .c_wready(c_wready), .c_bresp(), .c_bvalid(c_bvalid), .c_bready(1'b1), .c_araddr(c_araddr), .c_arvalid(c_arvalid),
        .c_arready(c_arready), .c_rdata(c_rdata), .c_rresp(), .c_rvalid(c_rvalid), .c_rready(1'b1), .irq(irq), .intx(intx),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awvalid(m_awvalid),
        .m_awready(m_awready), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(4'd0), .m_bresp(2'b00), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rid(4'd0), .m_rdata(m_rdata), .m_rresp(2'b00), .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready));

    // ---- memory (host 0..0x3FFFF, card from 0x40000), simple in-order slave; handshakes decided at the falling edge
    reg [7:0] mb [0:524287];
    function [7:0] pb(input [31:0] a);
        pb = a[7:0] ^ (a[15:8] * 3) ^ 8'h5A;
    endfunction
    function [7:0] pc(input [31:0] a);
        pc = ~pb(a) ^ 8'h33;
    endfunction
    reg [31:0] ra_q, wa_q;
    integer rbeats, rcnt, wcnt, k;
    reg rbusy = 1'b0, wbusy = 1'b0, wdone = 1'b0, r_fire = 1'b0, b_fire = 1'b0;
    always @(negedge clk) begin
        m_arready = 1'b0;
        if (!rbusy) begin
            if (m_arvalid) begin
                m_arready = 1'b1; ra_q = m_araddr; rbeats = m_arlen + 1; rcnt = 0; rbusy = 1'b1; m_rvalid = 1'b0; r_fire = 1'b0;
            end
        end else begin
            if (r_fire) begin
                rcnt = rcnt + 1; m_rvalid = 1'b0; r_fire = 1'b0;
                if (rcnt == rbeats) rbusy = 1'b0;
            end
            if (rbusy && !r_fire) begin
                for (k = 0; k < 8; k = k + 1) m_rdata[8*k +: 8] = mb[(ra_q + rcnt * 8 + k) & 32'h7FFFF];
                m_rlast = (rcnt == rbeats - 1);
                m_rvalid = 1'b1;
                r_fire = m_rready;
            end
        end
        m_awready = 1'b0; m_wready = 1'b0;
        if (!wbusy) begin
            if (m_awvalid) begin m_awready = 1'b1; wa_q = m_awaddr; wcnt = 0; wbusy = 1'b1; wdone = 1'b0; end
        end else if (!wdone) begin
            if (m_wvalid) begin
                m_wready = 1'b1;
                for (k = 0; k < 8; k = k + 1) mb[(wa_q + wcnt * 8 + k) & 32'h7FFFF] = m_wdata[8*k +: 8];
                wcnt = wcnt + 1;
                if (m_wlast) wdone = 1'b1;
            end
        end else if (b_fire) begin
            m_bvalid = 1'b0; b_fire = 1'b0; wbusy = 1'b0;
        end else begin
            m_bvalid = 1'b1; b_fire = m_bready;
        end
    end

    // ---- masters
    integer errors = 0, checks = 0;
    reg [31:0] rd_val;
    task hw(input [20:0] a, input [31:0] d);
        begin
            @(negedge clk); s_awaddr = a; s_wdata = d; s_awvalid = 1'b1;
            @(posedge clk); while (!s_awready) @(posedge clk);
            @(negedge clk); s_awvalid = 1'b0; s_wvalid = 1'b1;
            @(posedge clk); while (!s_wready) @(posedge clk);
            @(negedge clk); s_wvalid = 1'b0; #1 s_bready = 1'b1;
            @(posedge clk); while (!s_bvalid) @(posedge clk);
            @(negedge clk); s_bready = 1'b0;
        end
    endtask
    task hr(input [20:0] a);
        begin
            @(negedge clk); s_araddr = a; s_arvalid = 1'b1;
            @(posedge clk); while (!s_arready) @(posedge clk);
            @(negedge clk); s_arvalid = 1'b0; #1 s_rready = 1'b1;
            @(posedge clk); while (!s_rvalid) @(posedge clk);
            #1 rd_val = s_rdata;
            @(negedge clk); s_rready = 1'b0;
        end
    endtask
    task cw(input [6:0] a, input [31:0] d);
        begin
            @(negedge clk); c_awaddr = a; c_wdata = d; c_awvalid = 1'b1; c_wvalid = 1'b1;
            @(posedge clk); while (!(c_awready && c_wready)) @(posedge clk);
            @(negedge clk); c_awvalid = 1'b0; c_wvalid = 1'b0;
            @(posedge clk); while (!c_bvalid) @(posedge clk);
        end
    endtask
    task ev(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            checks = checks + 1;
            if (got !== want) begin errors = errors + 1; $display("FAIL %0s: got %08x want %08x", what, got, want); end
        end
    endtask
    task put32(input [31:0] a, input [31:0] d);
        begin mb[a] = d[7:0]; mb[a + 1] = d[15:8]; mb[a + 2] = d[23:16]; mb[a + 3] = d[31:24]; end
    endtask
    task put_desc(input [31:0] a, input [31:0] ctrl, input [31:0] len, input [31:0] src, input [31:0] dst);
        begin
            put32(a, ctrl); put32(a + 4, len); put32(a + 8, src); put32(a + 12, 32'd0);
            put32(a + 16, dst); put32(a + 20, 32'd0); put32(a + 24, 32'd0); put32(a + 28, 32'd0);
        end
    endtask
    integer i, bad, wt;
    // BAR1 registers: offsets as in the XDMA register map, BAR1 assigned to 0xF9150000 (window offset 0x150000); BAR0 at 0xF9130000
    localparam [20:0] B1 = 21'h150000;
    task b1w(input [15:0] off, input [31:0] d);
        hw(B1 + off, d);
    endtask
    task b1r(input [15:0] off);
        hr(B1 + off);
    endtask
    task wait_idle(input [15:0] stat);
        begin
            wt = 0; b1r(stat);
            while (rd_val[0] && wt < 2000) begin b1r(stat); wt = wt + 1; end
            ev("engine idle", wt < 2000, 1);
        end
    endtask
    initial begin
        for (i = 0; i < 524288; i = i + 1) mb[i] = pc(i);
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        // enumeration: IDs, BAR sizing, assignment, memory enable (bit 1 of the command register)
        hr({1'b0, 8'h00, 10'h00, 2'b00}); ev("ids", rd_val, 32'h903410EE);
        hw({1'b0, 8'h00, 10'h04, 2'b00}, 32'hF9130000);
        hw({1'b0, 8'h00, 10'h05, 2'b00}, 32'hF9150000);
        hw({1'b0, 8'h00, 10'h01, 2'b00}, 32'h00000006);
        // BAR0 still reaches the register block, BAR1 the DMA registers
        hr(21'h130000); ev("BAR0 id", rd_val, 32'h50434901);
        b1r(16'h0000); ev("BAR1 H2C id", rd_val, 32'h1FC00006);
        b1r(16'h1000); ev("BAR1 C2H id", rd_val, 32'h1FC10006);
        b1r(16'h2000); ev("BAR1 IRQ id", rd_val, 32'h1FC20006);
        b1r(16'h3000); ev("BAR1 config id", rd_val, 32'h1FC30006);
        hr(21'h130020); hw(21'h130020, 32'h13572468); hr(21'h130020); ev("BAR0 mailbox after BAR1 traffic", rd_val, 32'h13572468);
        // the firmware (CPU window) opens the card window: 0x40000, 128 KiB
        cw(7'h70, 32'h00040000); cw(7'h74, 32'h00020000);
        // H2C: host 0x1000 -> card 0x40100, 256 bytes
        for (i = 0; i < 256; i = i + 1) mb[32'h1000 + i] = pb(32'h1000 + i);
        put_desc(32'h100, 32'hAD4B0003, 32'd256, 32'h1000, 32'h40100);
        b1w(16'h4080, 32'h100); b1w(16'h4084, 32'd0); b1w(16'h0004, 32'h5);   // run + ie_descriptor_completed
        wait_idle(16'h0040);
        b1r(16'h0048); ev("H2C count", rd_val, 32'd1);
        bad = 0; for (i = 0; i < 256; i = i + 1) if (mb[32'h40100 + i] !== pb(32'h1000 + i)) bad = bad + 1;
        ev("H2C data", bad, 0);
        // the interrupt: gated by the IRQ block, cleared by the status read
        ev("no INTx before the channel enable", {31'd0, intx}, 0);
        b1w(16'h2014, 32'h1);
        repeat (3) @(negedge clk);
        ev("INTx after the channel enable", {31'd0, intx}, 1);
        hr({1'b0, 8'h00, 10'h01, 2'b00}); ev("config status INTx bit", rd_val[19], 1'b1);
        b1r(16'h0044); ev("H2C status", rd_val, 32'h00000006);
        repeat (3) @(negedge clk);
        ev("INTx cleared by the status read", {31'd0, intx}, 0);
        b1w(16'h0004, 32'h0);
        // C2H: card 0x40400 -> host 0x2000
        for (i = 0; i < 128; i = i + 1) mb[32'h40400 + i] = pb(32'h40400 + i);
        put_desc(32'h140, 32'hAD4B0003, 32'd128, 32'h40400, 32'h2000);
        b1w(16'h5080, 32'h140); b1w(16'h5084, 32'd0); b1w(16'h1004, 32'h1);
        wait_idle(16'h1040);
        bad = 0; for (i = 0; i < 128; i = i + 1) if (mb[32'h2000 + i] !== pb(32'h40400 + i)) bad = bad + 1;
        ev("C2H data", bad, 0);
        b1w(16'h1004, 32'h0);
        // the window protects card memory: outside it, nothing is written and the status says so
        put_desc(32'h100, 32'hAD4B0003, 32'd256, 32'h1000, 32'h70000);
        b1w(16'h4080, 32'h100); b1w(16'h0004, 32'h1);
        wait_idle(16'h0040);
        b1r(16'h0044); ev("outside the window: write error", rd_val, 32'h00004000);
        bad = 0; for (i = 0; i < 256; i = i + 1) if (mb[32'h70000 + i] !== pc(32'h70000 + i)) bad = bad + 1;
        ev("outside the window: untouched", bad, 0);
        b1w(16'h0004, 32'h0);
        // user interrupt: the CPU rings the host doorbell; it needs the IRQ block's user enable
        cw(7'h0C, 32'h1);
        repeat (3) @(negedge clk);
        ev("user interrupt masked without enable", {31'd0, intx}, 0);
        b1w(16'h2008, 32'h1);
        repeat (3) @(negedge clk);
        ev("user interrupt", {31'd0, intx}, 1);
        hw(21'h13000C, 32'h1);   // the host acknowledges through BAR0
        repeat (3) @(negedge clk);
        ev("user interrupt cleared", {31'd0, intx}, 0);
        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (errors == 0 && checks > 20) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin
        #50000000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
