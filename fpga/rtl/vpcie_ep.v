// SPDX-License-Identifier: MIT
// Logical PCIe endpoint for the CPU-as-root-complex variant (decision 0008): vpcie (config space and BAR decoder behind the generic ECAM host
// bridge) in front of the same pcie_regs block the real endpoint uses, so firmware serves it exactly as it serves the XDMA host. All in one clock
// (per_clk). The link is always up, PERST# released and the "PCIe clock" a local toggle, so STATUS reads like a trained link.
//   s_*  the 2 MiB window at 0xF9000000 (crossbar slave 13), c_* the CPU register window (crossbar slave 12, 0xF800A000)
//   irq   host -> CPU doorbell (PLIC source 9), intx  the device's INTx level toward the host bridge (PLIC source 10)
module vpcie_ep (
    input  wire        clk,
    input  wire        rst_n,
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
    output wire        intx
);
    wire [6:0]  h_awaddr, h_araddr;
    wire [31:0] h_wdata, h_rdata;
    wire [3:0]  h_wstrb;
    wire        h_awvalid, h_awready, h_wvalid, h_wready, h_bvalid, h_bready, h_arvalid, h_arready, h_rvalid, h_rready;
    wire [1:0]  h_bresp, h_rresp;
    wire        cpu_db_any;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] win_base, win_size;   // no DMA in this variant
    /* verilator lint_on UNUSEDSIGNAL */
    reg         aclk_tog = 1'b0;
    always @(posedge clk) aclk_tog <= ~aclk_tog;

    vpcie u_vpcie (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready), .s_araddr(s_araddr), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awaddr(h_awaddr), .m_awvalid(h_awvalid), .m_awready(h_awready), .m_wdata(h_wdata), .m_wstrb(h_wstrb), .m_wvalid(h_wvalid),
        .m_wready(h_wready), .m_bresp(h_bresp), .m_bvalid(h_bvalid), .m_bready(h_bready), .m_araddr(h_araddr), .m_arvalid(h_arvalid),
        .m_arready(h_arready), .m_rdata(h_rdata), .m_rresp(h_rresp), .m_rvalid(h_rvalid), .m_rready(h_rready),
        .intx_pending(cpu_db_any), .intx(intx));

    pcie_regs u_regs (
        .clk(clk), .rst_n(rst_n),
        .h_awaddr(h_awaddr), .h_awvalid(h_awvalid), .h_awready(h_awready), .h_wdata(h_wdata), .h_wstrb(h_wstrb), .h_wvalid(h_wvalid),
        .h_wready(h_wready), .h_bresp(h_bresp), .h_bvalid(h_bvalid), .h_bready(h_bready), .h_araddr(h_araddr), .h_arvalid(h_arvalid),
        .h_arready(h_arready), .h_rdata(h_rdata), .h_rresp(h_rresp), .h_rvalid(h_rvalid), .h_rready(h_rready),
        .c_awaddr(c_awaddr), .c_awvalid(c_awvalid), .c_awready(c_awready), .c_wdata(c_wdata), .c_wstrb(c_wstrb), .c_wvalid(c_wvalid),
        .c_wready(c_wready), .c_bresp(c_bresp), .c_bvalid(c_bvalid), .c_bready(c_bready), .c_araddr(c_araddr), .c_arvalid(c_arvalid),
        .c_arready(c_arready), .c_rdata(c_rdata), .c_rresp(c_rresp), .c_rvalid(c_rvalid), .c_rready(c_rready),
        .link_up_a(1'b1), .aclk_toggle_a(aclk_tog), .perst_n_a(1'b1), .win_base(win_base), .win_size(win_size), .irq(irq), .cpu_db_any(cpu_db_any));
endmodule
