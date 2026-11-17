// SPDX-License-Identifier: MIT
// Logical PCIe endpoint for the CPU-as-root-complex variant (decision 0008): vpcie (config space and BAR decoder behind the generic ECAM host
// bridge) in front of the same pcie_regs block the real endpoint uses, so firmware serves it exactly as it serves the XDMA host. All in one clock
// (per_clk), plus the DMA engine (vdma, XDMA-compatible registers behind BAR1) whose AXI master crosses to the CPU clock for the hub DMA port. The link is always up, PERST# released and the "PCIe clock" a local toggle, so STATUS reads like a trained link.
//   s_*  the 2 MiB window at 0xF9000000 (crossbar slave 13), c_* the CPU register window (crossbar slave 12, 0xF800A000)
//   irq   host -> CPU doorbell (PLIC source 9), intx  the device's INTx level toward the host bridge (PLIC source 10)
module vpcie_ep (
    input  wire        clk,         // per_clk
    input  wire        rst_n,
    input  wire        cclk,        // CPU clock, for the hub DMA port
    input  wire        crst_n,
    input  wire [20:0] s_awaddr,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,
    input  wire [20:0] s_araddr,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rvalid,
    input  wire        s_rready,
    input  wire [6:0]  c_awaddr,
    input  wire        c_awvalid,
    output wire        c_awready,
    input  wire [31:0] c_wdata,
    input  wire [3:0]  c_wstrb,
    input  wire        c_wvalid,
    output wire        c_wready,
    output wire [1:0]  c_bresp,
    output wire        c_bvalid,
    input  wire        c_bready,
    input  wire [6:0]  c_araddr,
    input  wire        c_arvalid,
    output wire        c_arready,
    output wire [31:0] c_rdata,
    output wire [1:0]  c_rresp,
    output wire        c_rvalid,
    input  wire        c_rready,
    output wire        irq,
    output wire        intx,
    // DMA master toward the hub DMA port (CPU clock, 64-bit, 4-bit ids as pcie_ep)
    output wire [3:0]  m_awid,
    output wire [31:0] m_awaddr,
    output wire [7:0]  m_awlen,
    output wire [2:0]  m_awsize,
    output wire [1:0]  m_awburst,
    output wire        m_awvalid,
    input  wire        m_awready,
    output wire [63:0] m_wdata,
    output wire [7:0]  m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,
    input  wire [3:0]  m_bid,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready,
    output wire [3:0]  m_arid,
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire [2:0]  m_arsize,
    output wire [1:0]  m_arburst,
    output wire        m_arvalid,
    input  wire        m_arready,
    input  wire [3:0]  m_rid,
    input  wire [63:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready
);
    // vpcie master port: BAR0 -> pcie_regs host window (h_*), BAR1 -> DMA registers (d_*)
    wire [15:0] v_awaddr, v_araddr;
    wire        v_awsel, v_arsel;
    wire [31:0] v_wdata, v_rdata;
    wire [3:0]  v_wstrb;
    wire        v_awvalid, v_awready, v_wvalid, v_wready, v_bvalid, v_bready, v_arvalid, v_arready, v_rvalid, v_rready;
    wire [1:0]  v_bresp, v_rresp;
    wire [31:0] h_rdata, d_rdata;
    wire [1:0]  h_bresp, h_rresp, d_bresp, d_rresp;
    wire        h_awready, h_wready, h_bvalid, h_arready, h_rvalid;
    wire        d_awready, d_wready, d_bvalid, d_arready, d_rvalid;
    // the select is stable from the cycle vpcie raises a valid until the response is taken (the write select also steers W and B)
    assign v_awready = v_awsel ? d_awready : h_awready;
    assign v_wready  = v_awsel ? d_wready : h_wready;
    assign v_bvalid  = v_awsel ? d_bvalid : h_bvalid;
    assign v_bresp   = v_awsel ? d_bresp : h_bresp;
    assign v_arready = v_arsel ? d_arready : h_arready;
    assign v_rvalid  = v_arsel ? d_rvalid : h_rvalid;
    assign v_rdata   = v_arsel ? d_rdata : h_rdata;
    assign v_rresp   = v_arsel ? d_rresp : h_rresp;
    wire cpu_db_any, dma_intx;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] win_base, win_size;
    /* verilator lint_on UNUSEDSIGNAL */
    reg         aclk_tog = 1'b0;
    always @(posedge clk) aclk_tog <= ~aclk_tog;

    vpcie u_vpcie (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready), .s_araddr(s_araddr), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awaddr(v_awaddr), .m_awsel(v_awsel), .m_awvalid(v_awvalid), .m_awready(v_awready), .m_wdata(v_wdata), .m_wstrb(v_wstrb),
        .m_wvalid(v_wvalid), .m_wready(v_wready), .m_bresp(v_bresp), .m_bvalid(v_bvalid), .m_bready(v_bready),
        .m_araddr(v_araddr), .m_arsel(v_arsel), .m_arvalid(v_arvalid), .m_arready(v_arready), .m_rdata(v_rdata), .m_rresp(v_rresp),
        .m_rvalid(v_rvalid), .m_rready(v_rready),
        .intx_pending(dma_intx), .intx(intx));

    pcie_regs u_regs (
        .clk(clk), .rst_n(rst_n),
        .h_awaddr(v_awaddr[6:0]), .h_awvalid(v_awvalid && !v_awsel), .h_awready(h_awready), .h_wdata(v_wdata), .h_wstrb(v_wstrb),
        .h_wvalid(v_wvalid && !v_awsel), .h_wready(h_wready), .h_bresp(h_bresp), .h_bvalid(h_bvalid), .h_bready(v_bready && !v_awsel),
        .h_araddr(v_araddr[6:0]), .h_arvalid(v_arvalid && !v_arsel), .h_arready(h_arready), .h_rdata(h_rdata), .h_rresp(h_rresp),
        .h_rvalid(h_rvalid), .h_rready(v_rready && !v_arsel),
        .c_awaddr(c_awaddr), .c_awvalid(c_awvalid), .c_awready(c_awready), .c_wdata(c_wdata), .c_wstrb(c_wstrb), .c_wvalid(c_wvalid),
        .c_wready(c_wready), .c_bresp(c_bresp), .c_bvalid(c_bvalid), .c_bready(c_bready), .c_araddr(c_araddr), .c_arvalid(c_arvalid),
        .c_arready(c_arready), .c_rdata(c_rdata), .c_rresp(c_rresp), .c_rvalid(c_rvalid), .c_rready(c_rready),
        .link_up_a(1'b1), .aclk_toggle_a(aclk_tog), .perst_n_a(1'b1), .win_base(win_base), .win_size(win_size), .irq(irq), .cpu_db_any(cpu_db_any));

    // ---- DMA engine, per_clk -> clock converter -> hub DMA port
    wire [31:0] e_awaddr, e_araddr;
    wire [7:0]  e_awlen, e_arlen;
    wire [63:0] e_wdata, e_rdata;
    wire [1:0]  e_bresp, e_rresp;
    wire        e_awvalid, e_awready, e_wlast, e_wvalid, e_wready, e_bvalid, e_bready, e_arvalid, e_arready, e_rlast, e_rvalid, e_rready;
    vdma u_vdma (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(v_awaddr), .s_awvalid(v_awvalid && v_awsel), .s_awready(d_awready), .s_wdata(v_wdata), .s_wstrb(v_wstrb),
        .s_wvalid(v_wvalid && v_awsel), .s_wready(d_wready), .s_bresp(d_bresp), .s_bvalid(d_bvalid), .s_bready(v_bready && v_awsel),
        .s_araddr(v_araddr), .s_arvalid(v_arvalid && v_arsel), .s_arready(d_arready), .s_rdata(d_rdata), .s_rresp(d_rresp),
        .s_rvalid(d_rvalid), .s_rready(v_rready && v_arsel),
        .m_awaddr(e_awaddr), .m_awlen(e_awlen), .m_awvalid(e_awvalid), .m_awready(e_awready), .m_wdata(e_wdata), .m_wlast(e_wlast),
        .m_wvalid(e_wvalid), .m_wready(e_wready), .m_bresp(e_bresp), .m_bvalid(e_bvalid), .m_bready(e_bready),
        .m_araddr(e_araddr), .m_arlen(e_arlen), .m_arvalid(e_arvalid), .m_arready(e_arready), .m_rdata(e_rdata), .m_rresp(e_rresp),
        .m_rlast(e_rlast), .m_rvalid(e_rvalid), .m_rready(e_rready),
        .win_base(win_base), .win_size(win_size), .user_req(cpu_db_any), .intx(dma_intx));

    vdma_cc u_cc (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awid(4'd0), .s_axi_awaddr(e_awaddr), .s_axi_awlen(e_awlen), .s_axi_awsize(3'd3), .s_axi_awburst(2'b01),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'd0), .s_axi_awprot(3'd0), .s_axi_awregion(4'd0), .s_axi_awqos(4'd0),
        .s_axi_awvalid(e_awvalid), .s_axi_awready(e_awready),
        .s_axi_wdata(e_wdata), .s_axi_wstrb(8'hFF), .s_axi_wlast(e_wlast), .s_axi_wvalid(e_wvalid), .s_axi_wready(e_wready),
        .s_axi_bid(), .s_axi_bresp(e_bresp), .s_axi_bvalid(e_bvalid), .s_axi_bready(e_bready),
        .s_axi_arid(4'd0), .s_axi_araddr(e_araddr), .s_axi_arlen(e_arlen), .s_axi_arsize(3'd3), .s_axi_arburst(2'b01),
        .s_axi_arlock(1'b0), .s_axi_arcache(4'd0), .s_axi_arprot(3'd0), .s_axi_arregion(4'd0), .s_axi_arqos(4'd0),
        .s_axi_arvalid(e_arvalid), .s_axi_arready(e_arready),
        .s_axi_rid(), .s_axi_rdata(e_rdata), .s_axi_rresp(e_rresp), .s_axi_rlast(e_rlast), .s_axi_rvalid(e_rvalid), .s_axi_rready(e_rready),
        .m_axi_aclk(cclk), .m_axi_aresetn(crst_n),
        .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
        .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(), .m_axi_awregion(), .m_axi_awqos(),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast), .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bid(m_bid), .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen), .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arregion(), .m_axi_arqos(),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rid(m_rid), .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready));
endmodule
