// SPDX-License-Identifier: MIT
// PCIe endpoint of the HG-XCKU5P edge connector (Gen3 x4, PCIE4 block X0Y0, GTY quad 224): the XDMA core, its converters, the host/CPU
// register block and the DMA window filter. Clock domains: the PCIe user clock `axi_aclk` (250 MHz, exists only while the slot supplies a
// reference clock), `clk` (CPU clock, memory port) and `per_clk` (peripheral registers). Nothing on the CPU side waits for the PCIe clock: the
// converters hold their CPU-side ports idle while it is absent, and the status register reports it.
//
// Host view: BAR0 = 64 KiB AXI4-Lite window onto the 128-byte pcie_regs map (aliased), BAR1 = XDMA registers (the core's own layout; the
// descriptor engines read host memory and move data to/from the AXI address given in each descriptor). DMA bursts reach CPU memory
// through axi_win: nothing is reachable until the CPU programs WIN_BASE/WIN_SIZE (registers below), so a host cannot touch DDR by default.
//
// CPU registers (per_clk window, 7-bit word address; same map as the host plus):
//   0x70 WIN_BASE  DMA window base (CPU only)
//   0x74 WIN_SIZE  DMA window size in bytes, 0 = closed (CPU only)
// The window registers cross into the CPU clock through `cdc_cfg` (a toggle handshake; the registers change at most every few per_clk cycles).
module pcie_ep (
    input  wire        sys_clk_p,
    input  wire        sys_clk_n,
    input  wire        sys_rst_n,       // PERST# from the slot (active low)
    output wire [3:0]  pci_exp_txp,
    output wire [3:0]  pci_exp_txn,
    input  wire [3:0]  pci_exp_rxp,
    input  wire [3:0]  pci_exp_rxn,
`ifdef PCIE_SIM_PIPE
    input  wire [25:0] common_commands_in,
    output wire [25:0] common_commands_out,
    input  wire [83:0] pipe_rx_0_sigs,
    input  wire [83:0] pipe_rx_1_sigs,
    input  wire [83:0] pipe_rx_2_sigs,
    input  wire [83:0] pipe_rx_3_sigs,
    input  wire [83:0] pipe_rx_4_sigs,
    input  wire [83:0] pipe_rx_5_sigs,
    input  wire [83:0] pipe_rx_6_sigs,
    input  wire [83:0] pipe_rx_7_sigs,
    input  wire [83:0] pipe_rx_8_sigs,
    input  wire [83:0] pipe_rx_9_sigs,
    input  wire [83:0] pipe_rx_10_sigs,
    input  wire [83:0] pipe_rx_11_sigs,
    input  wire [83:0] pipe_rx_12_sigs,
    input  wire [83:0] pipe_rx_13_sigs,
    input  wire [83:0] pipe_rx_14_sigs,
    input  wire [83:0] pipe_rx_15_sigs,
    output wire [83:0] pipe_tx_0_sigs,
    output wire [83:0] pipe_tx_1_sigs,
    output wire [83:0] pipe_tx_2_sigs,
    output wire [83:0] pipe_tx_3_sigs,
    output wire [83:0] pipe_tx_4_sigs,
    output wire [83:0] pipe_tx_5_sigs,
    output wire [83:0] pipe_tx_6_sigs,
    output wire [83:0] pipe_tx_7_sigs,
    output wire [83:0] pipe_tx_8_sigs,
    output wire [83:0] pipe_tx_9_sigs,
    output wire [83:0] pipe_tx_10_sigs,
    output wire [83:0] pipe_tx_11_sigs,
    output wire [83:0] pipe_tx_12_sigs,
    output wire [83:0] pipe_tx_13_sigs,
    output wire [83:0] pipe_tx_14_sigs,
    output wire [83:0] pipe_tx_15_sigs,
`endif
    input  wire        clk,             // CPU clock
    input  wire        rst_n,
    input  wire        per_clk,         // peripheral clock
    input  wire        per_rst_n,
    // CPU-clock AXI4 master (64-bit data, 32-bit address) towards the hub DMA port
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
    output wire        m_rready,
    // CPU register window (AXI4-Lite, per_clk)
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
`ifdef NOCPU
    // CPU-less build (decision 0008, variant 3): the host's BAR0 (64 KiB) is a master port onto the peripheral crossbar (AXI4-Lite, per_clk); offset = low 16
    // address bits, the crossbar window being 0xF8000000. The host-side port of the register block is idle then (its registers are at BAR0 + 0xA000 via c_*).
    output wire [15:0] hl_awaddr,
    output wire        hl_awvalid,
    input  wire        hl_awready,
    output wire [31:0] hl_wdata,
    output wire [3:0]  hl_wstrb,
    output wire        hl_wvalid,
    input  wire        hl_wready,
    input  wire [1:0]  hl_bresp,
    input  wire        hl_bvalid,
    output wire        hl_bready,
    output wire [15:0] hl_araddr,
    output wire        hl_arvalid,
    input  wire        hl_arready,
    input  wire [31:0] hl_rdata,
    input  wire [1:0]  hl_rresp,
    input  wire        hl_rvalid,
    output wire        hl_rready,
`endif
    output wire        irq,            // host doorbell pending and enabled (level, per_clk)
    // user interrupts to the host: uirq[i] is a level from any clock domain; vector i+1 (vector 0 is the CPU doorbell); uirq_pend = request outstanding
    input  wire [6:0]  uirq,
    output wire [6:0]  uirq_pend,
    output wire [6:0]  uirq_seen    // the levels as seen in the PCIe clock domain (also with no link, when requests are not raised)
);
    // ------------------------------------------------------------ pins
    wire sys_clk, sys_clk_gt, perst_n;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) u_refclk (.O(sys_clk_gt), .ODIV2(sys_clk), .I(sys_clk_p), .CEB(1'b0), .IB(sys_clk_n));
    IBUF u_perst (.O(perst_n), .I(sys_rst_n));

    // ------------------------------------------------------------ XDMA core
    wire        axi_aclk, axi_aresetn, user_lnk_up;
    wire [7:0]  usr_irq_ack;
    wire [7:0]  usr_irq_req;
    wire [3:0]  x_awid, x_bid, x_arid, x_rid;
    wire [63:0] x_awaddr, x_araddr;
    wire [7:0]  x_awlen, x_arlen;
    wire [2:0]  x_awsize, x_arsize, x_awprot, x_arprot;
    wire [1:0]  x_awburst, x_arburst, x_bresp, x_rresp;
    wire        x_awlock, x_arlock, x_awvalid, x_awready, x_wlast, x_wvalid, x_wready, x_bvalid, x_bready;
    wire        x_arvalid, x_arready, x_rlast, x_rvalid, x_rready;
    wire [3:0]  x_awcache, x_arcache;
    wire [127:0] x_wdata, x_rdata;
    wire [15:0] x_wstrb;
    wire [31:0] xl_awaddr, xl_wdata, xl_araddr, xl_rdata;
    wire [3:0]  xl_wstrb;
    wire [2:0]  xl_awprot, xl_arprot;
    wire [1:0]  xl_bresp, xl_rresp;
    wire        xl_awvalid, xl_awready, xl_wvalid, xl_wready, xl_bvalid, xl_bready, xl_arvalid, xl_arready, xl_rvalid, xl_rready;
    /* verilator lint_off PINMISSING */
    xdma_0 u_xdma (
        .sys_clk(sys_clk), .sys_clk_gt(sys_clk_gt), .sys_rst_n(perst_n),
        .user_lnk_up(user_lnk_up),
        .pci_exp_txp(pci_exp_txp), .pci_exp_txn(pci_exp_txn), .pci_exp_rxp(pci_exp_rxp), .pci_exp_rxn(pci_exp_rxn),
        .axi_aclk(axi_aclk), .axi_aresetn(axi_aresetn),
        .usr_irq_req(usr_irq_req), .usr_irq_ack(usr_irq_ack), .msi_enable(), .msi_vector_width(),
`ifdef PCIE_SIM_PIPE
        .common_commands_in(common_commands_in), .common_commands_out(common_commands_out),
        .pipe_rx_0_sigs(pipe_rx_0_sigs),
        .pipe_rx_1_sigs(pipe_rx_1_sigs),
        .pipe_rx_2_sigs(pipe_rx_2_sigs),
        .pipe_rx_3_sigs(pipe_rx_3_sigs),
        .pipe_rx_4_sigs(pipe_rx_4_sigs),
        .pipe_rx_5_sigs(pipe_rx_5_sigs),
        .pipe_rx_6_sigs(pipe_rx_6_sigs),
        .pipe_rx_7_sigs(pipe_rx_7_sigs),
        .pipe_rx_8_sigs(pipe_rx_8_sigs),
        .pipe_rx_9_sigs(pipe_rx_9_sigs),
        .pipe_rx_10_sigs(pipe_rx_10_sigs),
        .pipe_rx_11_sigs(pipe_rx_11_sigs),
        .pipe_rx_12_sigs(pipe_rx_12_sigs),
        .pipe_rx_13_sigs(pipe_rx_13_sigs),
        .pipe_rx_14_sigs(pipe_rx_14_sigs),
        .pipe_rx_15_sigs(pipe_rx_15_sigs),
        .pipe_tx_0_sigs(pipe_tx_0_sigs),
        .pipe_tx_1_sigs(pipe_tx_1_sigs),
        .pipe_tx_2_sigs(pipe_tx_2_sigs),
        .pipe_tx_3_sigs(pipe_tx_3_sigs),
        .pipe_tx_4_sigs(pipe_tx_4_sigs),
        .pipe_tx_5_sigs(pipe_tx_5_sigs),
        .pipe_tx_6_sigs(pipe_tx_6_sigs),
        .pipe_tx_7_sigs(pipe_tx_7_sigs),
        .pipe_tx_8_sigs(pipe_tx_8_sigs),
        .pipe_tx_9_sigs(pipe_tx_9_sigs),
        .pipe_tx_10_sigs(pipe_tx_10_sigs),
        .pipe_tx_11_sigs(pipe_tx_11_sigs),
        .pipe_tx_12_sigs(pipe_tx_12_sigs),
        .pipe_tx_13_sigs(pipe_tx_13_sigs),
        .pipe_tx_14_sigs(pipe_tx_14_sigs),
        .pipe_tx_15_sigs(pipe_tx_15_sigs),
`endif
        .m_axi_awid(x_awid), .m_axi_awaddr(x_awaddr), .m_axi_awlen(x_awlen), .m_axi_awsize(x_awsize), .m_axi_awburst(x_awburst),
        .m_axi_awprot(x_awprot), .m_axi_awvalid(x_awvalid), .m_axi_awready(x_awready), .m_axi_awlock(x_awlock), .m_axi_awcache(x_awcache),
        .m_axi_wdata(x_wdata), .m_axi_wstrb(x_wstrb), .m_axi_wlast(x_wlast), .m_axi_wvalid(x_wvalid), .m_axi_wready(x_wready),
        .m_axi_bid(x_bid), .m_axi_bresp(x_bresp), .m_axi_bvalid(x_bvalid), .m_axi_bready(x_bready),
        .m_axi_arid(x_arid), .m_axi_araddr(x_araddr), .m_axi_arlen(x_arlen), .m_axi_arsize(x_arsize), .m_axi_arburst(x_arburst),
        .m_axi_arprot(x_arprot), .m_axi_arvalid(x_arvalid), .m_axi_arready(x_arready), .m_axi_arlock(x_arlock), .m_axi_arcache(x_arcache),
        .m_axi_rid(x_rid), .m_axi_rdata(x_rdata), .m_axi_rresp(x_rresp), .m_axi_rlast(x_rlast), .m_axi_rvalid(x_rvalid), .m_axi_rready(x_rready),
        .m_axil_awaddr(xl_awaddr), .m_axil_awprot(xl_awprot), .m_axil_awvalid(xl_awvalid), .m_axil_awready(xl_awready),
        .m_axil_wdata(xl_wdata), .m_axil_wstrb(xl_wstrb), .m_axil_wvalid(xl_wvalid), .m_axil_wready(xl_wready),
        .m_axil_bvalid(xl_bvalid), .m_axil_bresp(xl_bresp), .m_axil_bready(xl_bready),
        .m_axil_araddr(xl_araddr), .m_axil_arprot(xl_arprot), .m_axil_arvalid(xl_arvalid), .m_axil_arready(xl_arready),
        .m_axil_rdata(xl_rdata), .m_axil_rresp(xl_rresp), .m_axil_rvalid(xl_rvalid), .m_axil_rready(xl_rready));
    /* verilator lint_on PINMISSING */

    // ------------------------------------------------------------ DMA master: 128 -> 64 bit (the downsizer keeps the ids on its slave side only), then into the CPU clock
    wire [63:0] d_awaddr, d_araddr, d_wdata, d_rdata;
    wire [7:0]  d_awlen, d_arlen, d_wstrb;
    wire [2:0]  d_awsize, d_arsize;
    wire [1:0]  d_awburst, d_arburst, d_bresp, d_rresp;
    wire        d_awvalid, d_awready, d_wlast, d_wvalid, d_wready, d_bvalid, d_bready, d_arvalid, d_arready, d_rlast, d_rvalid, d_rready;
    pcie_dw u_dw (
        .s_axi_aclk(axi_aclk), .s_axi_aresetn(axi_aresetn),
        .s_axi_awid(x_awid), .s_axi_awaddr(x_awaddr), .s_axi_awlen(x_awlen), .s_axi_awsize(x_awsize), .s_axi_awburst(x_awburst),
        .s_axi_awlock(x_awlock), .s_axi_awcache(x_awcache), .s_axi_awprot(x_awprot), .s_axi_awregion(4'd0), .s_axi_awqos(4'd0),
        .s_axi_awvalid(x_awvalid), .s_axi_awready(x_awready),
        .s_axi_wdata(x_wdata), .s_axi_wstrb(x_wstrb), .s_axi_wlast(x_wlast), .s_axi_wvalid(x_wvalid), .s_axi_wready(x_wready),
        .s_axi_bid(x_bid), .s_axi_bresp(x_bresp), .s_axi_bvalid(x_bvalid), .s_axi_bready(x_bready),
        .s_axi_arid(x_arid), .s_axi_araddr(x_araddr), .s_axi_arlen(x_arlen), .s_axi_arsize(x_arsize), .s_axi_arburst(x_arburst),
        .s_axi_arlock(x_arlock), .s_axi_arcache(x_arcache), .s_axi_arprot(x_arprot), .s_axi_arregion(4'd0), .s_axi_arqos(4'd0),
        .s_axi_arvalid(x_arvalid), .s_axi_arready(x_arready),
        .s_axi_rid(x_rid), .s_axi_rdata(x_rdata), .s_axi_rresp(x_rresp), .s_axi_rlast(x_rlast), .s_axi_rvalid(x_rvalid), .s_axi_rready(x_rready),
        .m_axi_awaddr(d_awaddr), .m_axi_awlen(d_awlen), .m_axi_awsize(d_awsize), .m_axi_awburst(d_awburst),
        .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(), .m_axi_awregion(), .m_axi_awqos(),
        .m_axi_awvalid(d_awvalid), .m_axi_awready(d_awready),
        .m_axi_wdata(d_wdata), .m_axi_wstrb(d_wstrb), .m_axi_wlast(d_wlast), .m_axi_wvalid(d_wvalid), .m_axi_wready(d_wready),
        .m_axi_bresp(d_bresp), .m_axi_bvalid(d_bvalid), .m_axi_bready(d_bready),
        .m_axi_araddr(d_araddr), .m_axi_arlen(d_arlen), .m_axi_arsize(d_arsize), .m_axi_arburst(d_arburst),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arregion(), .m_axi_arqos(),
        .m_axi_arvalid(d_arvalid), .m_axi_arready(d_arready),
        .m_axi_rdata(d_rdata), .m_axi_rresp(d_rresp), .m_axi_rlast(d_rlast), .m_axi_rvalid(d_rvalid), .m_axi_rready(d_rready));

    wire [3:0]  w_awid, w_bid, w_arid, w_rid;
    wire [63:0] w_awaddr, w_araddr, w_wdata, w_rdata;
    wire [7:0]  w_awlen, w_arlen, w_wstrb;
    wire [2:0]  w_awsize, w_arsize;
    wire [1:0]  w_awburst, w_arburst, w_bresp, w_rresp;
    wire        w_awvalid, w_awready, w_wlast, w_wvalid, w_wready, w_bvalid, w_bready, w_arvalid, w_arready, w_rlast, w_rvalid, w_rready;
    pcie_cc u_cc (
        .s_axi_aclk(axi_aclk), .s_axi_aresetn(axi_aresetn),
        .s_axi_awid(4'd0), .s_axi_awaddr(d_awaddr), .s_axi_awlen(d_awlen), .s_axi_awsize(d_awsize), .s_axi_awburst(d_awburst),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'd0), .s_axi_awprot(3'd0), .s_axi_awregion(4'd0), .s_axi_awqos(4'd0),
        .s_axi_awvalid(d_awvalid), .s_axi_awready(d_awready),
        .s_axi_wdata(d_wdata), .s_axi_wstrb(d_wstrb), .s_axi_wlast(d_wlast), .s_axi_wvalid(d_wvalid), .s_axi_wready(d_wready),
        .s_axi_bid(), .s_axi_bresp(d_bresp), .s_axi_bvalid(d_bvalid), .s_axi_bready(d_bready),
        .s_axi_arid(4'd0), .s_axi_araddr(d_araddr), .s_axi_arlen(d_arlen), .s_axi_arsize(d_arsize), .s_axi_arburst(d_arburst),
        .s_axi_arlock(1'b0), .s_axi_arcache(4'd0), .s_axi_arprot(3'd0), .s_axi_arregion(4'd0), .s_axi_arqos(4'd0),
        .s_axi_arvalid(d_arvalid), .s_axi_arready(d_arready),
        .s_axi_rid(), .s_axi_rdata(d_rdata), .s_axi_rresp(d_rresp), .s_axi_rlast(d_rlast), .s_axi_rvalid(d_rvalid), .s_axi_rready(d_rready),
        .m_axi_aclk(clk), .m_axi_aresetn(rst_n),
        .m_axi_awid(w_awid), .m_axi_awaddr(w_awaddr), .m_axi_awlen(w_awlen), .m_axi_awsize(w_awsize), .m_axi_awburst(w_awburst),
        .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(), .m_axi_awregion(), .m_axi_awqos(),
        .m_axi_awvalid(w_awvalid), .m_axi_awready(w_awready),
        .m_axi_wdata(w_wdata), .m_axi_wstrb(w_wstrb), .m_axi_wlast(w_wlast), .m_axi_wvalid(w_wvalid), .m_axi_wready(w_wready),
        .m_axi_bid(w_bid), .m_axi_bresp(w_bresp), .m_axi_bvalid(w_bvalid), .m_axi_bready(w_bready),
        .m_axi_arid(w_arid), .m_axi_araddr(w_araddr), .m_axi_arlen(w_arlen), .m_axi_arsize(w_arsize), .m_axi_arburst(w_arburst),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arregion(), .m_axi_arqos(),
        .m_axi_arvalid(w_arvalid), .m_axi_arready(w_arready),
        .m_axi_rid(w_rid), .m_axi_rdata(w_rdata), .m_axi_rresp(w_rresp), .m_axi_rlast(w_rlast), .m_axi_rvalid(w_rvalid), .m_axi_rready(w_rready));

    // window registers (per_clk) -> CPU clock
    wire [31:0] win_base_p, win_size_p, win_base, win_size;
    cdc_cfg #(.W(64)) u_cdc_win (.src_clk(per_clk), .src_rst_n(per_rst_n), .d({win_size_p, win_base_p}),
                                 .dst_clk(clk), .dst_rst_n(rst_n), .q({win_size, win_base}));

    axi_win #(.DW(64), .IDW(4)) u_win (
        .clk(clk), .rst_n(rst_n), .win_base(win_base), .win_size(win_size),
        .s_awid(w_awid), .s_awaddr(w_awaddr[31:0]), .s_awhi(|w_awaddr[63:32]), .s_awlen(w_awlen), .s_awsize(w_awsize), .s_awburst(w_awburst),
        .s_awvalid(w_awvalid), .s_awready(w_awready), .s_wdata(w_wdata), .s_wstrb(w_wstrb), .s_wlast(w_wlast), .s_wvalid(w_wvalid),
        .s_wready(w_wready), .s_bid(w_bid), .s_bresp(w_bresp), .s_bvalid(w_bvalid), .s_bready(w_bready),
        .s_arid(w_arid), .s_araddr(w_araddr[31:0]), .s_arhi(|w_araddr[63:32]), .s_arlen(w_arlen), .s_arsize(w_arsize), .s_arburst(w_arburst),
        .s_arvalid(w_arvalid), .s_arready(w_arready), .s_rid(w_rid), .s_rdata(w_rdata), .s_rresp(w_rresp), .s_rlast(w_rlast),
        .s_rvalid(w_rvalid), .s_rready(w_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awvalid(m_awvalid),
        .m_awready(m_awready), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast), .m_rvalid(m_rvalid),
        .m_rready(m_rready));

    // ------------------------------------------------------------ host register window: PCIe clock -> peripheral clock
    wire [31:0] h_awaddr, h_wdata, h_araddr, h_rdata;
    wire [3:0]  h_wstrb;
    wire [2:0]  h_awprot, h_arprot;
    wire [1:0]  h_bresp, h_rresp;
    wire        h_awvalid, h_awready, h_wvalid, h_wready, h_bvalid, h_bready, h_arvalid, h_arready, h_rvalid, h_rready;
    pcie_ccl u_ccl (
        .s_axi_aclk(axi_aclk), .s_axi_aresetn(axi_aresetn),
        .s_axi_awaddr(xl_awaddr), .s_axi_awprot(xl_awprot), .s_axi_awvalid(xl_awvalid), .s_axi_awready(xl_awready),
        .s_axi_wdata(xl_wdata), .s_axi_wstrb(xl_wstrb), .s_axi_wvalid(xl_wvalid), .s_axi_wready(xl_wready),
        .s_axi_bresp(xl_bresp), .s_axi_bvalid(xl_bvalid), .s_axi_bready(xl_bready),
        .s_axi_araddr(xl_araddr), .s_axi_arprot(xl_arprot), .s_axi_arvalid(xl_arvalid), .s_axi_arready(xl_arready),
        .s_axi_rdata(xl_rdata), .s_axi_rresp(xl_rresp), .s_axi_rvalid(xl_rvalid), .s_axi_rready(xl_rready),
        .m_axi_aclk(per_clk), .m_axi_aresetn(per_rst_n),
        .m_axi_awaddr(h_awaddr), .m_axi_awprot(h_awprot), .m_axi_awvalid(h_awvalid), .m_axi_awready(h_awready),
        .m_axi_wdata(h_wdata), .m_axi_wstrb(h_wstrb), .m_axi_wvalid(h_wvalid), .m_axi_wready(h_wready),
        .m_axi_bresp(h_bresp), .m_axi_bvalid(h_bvalid), .m_axi_bready(h_bready),
        .m_axi_araddr(h_araddr), .m_axi_arprot(h_arprot), .m_axi_arvalid(h_arvalid), .m_axi_arready(h_arready),
        .m_axi_rdata(h_rdata), .m_axi_rresp(h_rresp), .m_axi_rvalid(h_rvalid), .m_axi_rready(h_rready));

    reg aclk_tog = 1'b0;
    always @(posedge axi_aclk) aclk_tog <= ~aclk_tog;
    wire cpu_db_any;
    pcie_regs u_regs (
        .clk(per_clk), .rst_n(per_rst_n),
        `ifdef NOCPU
        .h_awaddr(7'd0), .h_awvalid(1'b0), .h_awready(), .h_wdata(32'd0), .h_wstrb(4'd0), .h_wvalid(1'b0), .h_wready(), .h_bresp(), .h_bvalid(),
        .h_bready(1'b1), .h_araddr(7'd0), .h_arvalid(1'b0), .h_arready(), .h_rdata(), .h_rresp(), .h_rvalid(), .h_rready(1'b1),
`else
        .h_awaddr(h_awaddr[6:0]), .h_awvalid(h_awvalid), .h_awready(h_awready), .h_wdata(h_wdata), .h_wstrb(h_wstrb), .h_wvalid(h_wvalid),
        .h_wready(h_wready), .h_bresp(h_bresp), .h_bvalid(h_bvalid), .h_bready(h_bready),
        .h_araddr(h_araddr[6:0]), .h_arvalid(h_arvalid), .h_arready(h_arready), .h_rdata(h_rdata), .h_rresp(h_rresp), .h_rvalid(h_rvalid),
        .h_rready(h_rready),
`endif
        .c_awaddr(c_awaddr), .c_awvalid(c_awvalid), .c_awready(c_awready), .c_wdata(c_wdata), .c_wstrb(c_wstrb), .c_wvalid(c_wvalid),
        .c_wready(c_wready), .c_bresp(c_bresp), .c_bvalid(c_bvalid), .c_bready(c_bready),
        .c_araddr(c_araddr), .c_arvalid(c_arvalid), .c_arready(c_arready), .c_rdata(c_rdata), .c_rresp(c_rresp), .c_rvalid(c_rvalid),
        .c_rready(c_rready),
        .link_up_a(user_lnk_up), .aclk_toggle_a(aclk_tog), .perst_n_a(perst_n),
        .win_base(win_base_p), .win_size(win_size_p), .irq(irq), .cpu_db_any(cpu_db_any));
`ifdef NOCPU
    assign hl_awaddr = h_awaddr[15:0];
    assign hl_awvalid = h_awvalid;
    assign h_awready = hl_awready;
    assign hl_wdata = h_wdata;
    assign hl_wstrb = h_wstrb;
    assign hl_wvalid = h_wvalid;
    assign h_wready = hl_wready;
    assign h_bresp = hl_bresp;
    assign h_bvalid = hl_bvalid;
    assign hl_bready = h_bready;
    assign hl_araddr = h_araddr[15:0];
    assign hl_arvalid = h_arvalid;
    assign h_arready = hl_arready;
    assign h_rdata = hl_rdata;
    assign h_rresp = hl_rresp;
    assign h_rvalid = hl_rvalid;
    assign hl_rready = h_rready;
    wire unused_h = &{1'b0, h_awaddr[31:16], h_araddr[31:16], h_awprot, h_arprot};
`else
    // unused high address / protection bits of the host window
    wire unused_h = &{1'b0, h_awaddr[31:7], h_araddr[31:7], h_awprot, h_arprot};
`endif

    // ------------------------------------------------------------ interrupts to the host (MSI/INTx through the XDMA user interrupts, 8 vectors)
    // vector 0: a CPU doorbell bit is pending; vectors 1..7: uirq[0..6] (irq_req.v: one request per assertion)
    wire seen0;
    wire [6:0] seen_u;
    irq_req u_irq0 (.clk(axi_aclk), .rst_n(axi_aresetn), .lvl(cpu_db_any), .ack(usr_irq_ack[0]), .req(usr_irq_req[0]), .seen(seen0));
    genvar gi;
    generate
        for (gi = 0; gi < 7; gi = gi + 1) begin : g_uirq
            irq_req u_irq (.clk(axi_aclk), .rst_n(axi_aresetn), .lvl(uirq[gi]), .ack(usr_irq_ack[gi+1]), .req(usr_irq_req[gi+1]), .seen(seen_u[gi]));
        end
    endgenerate
    // requests in flight, back to the register clock for the user block (two flops; a level that changes only when software acts)
    (* ASYNC_REG = "TRUE" *) reg [6:0] pend_s1, pend_s2, seen_s1, seen_s2;
    always @(posedge per_clk) begin
        pend_s1 <= usr_irq_req[7:1];
        pend_s2 <= pend_s1;
        seen_s1 <= seen_u;
        seen_s2 <= seen_s1;
    end
    assign uirq_pend = pend_s2;
    assign uirq_seen = seen_s2;
    wire unused_seen0 = seen0;
endmodule
