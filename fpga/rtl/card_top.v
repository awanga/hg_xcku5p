// SPDX-License-Identifier: MIT
// CPU-less PCIe card (build_soc.tcl -card, decision 0008 variant 3, lean form): DDR4 controller + PCIe endpoint (XDMA, edge connector) + a small register
// map; none of the board peripherals (SD, Ethernet, HDMI, I2C, SPI, GPIO, UART1, fan) exist. The UART2 rig (nocpu_core) can drive the same buses when no
// host is attached. The full-peripheral CPU-less build stays available as `-nocpu -pcie` (soc_top).
//
// Clocks: ui_clk (333.33 MHz at tCK 750 ps) runs the DDR4 interface, the rig and the PCIe DMA path; per_clk (100 MHz, MMCM on CLK_50M) runs the register
// crossbar and the register blocks. Reset: the ui_clk side is held until DDR4 calibration completes.
// BAR0 map (host offset = rig address - 0xF8000000; unmapped words answer DECERR from the crossbar):
//   0x1000 card_regs   identity, build, status, scratch, LED (fpga/rtl/card_regs.v)
//   0x2000 user_regs   hook window for future firmware functions (fpga/rtl/user_regs.v)
//   0xA000 pcie_regs   mailbox, doorbells, DMA window (same block as the CPU builds)
//   0x3000..0x9FFF, 0xB000..0xFFFF reserved
// DMA: the XDMA master reaches DDR4 (0x40000000, 1 GiB) through the window of pcie_regs, closed at reset; the host or the rig opens it (BAR0 + 0xA070/0xA074).
module card_top #(
    parameter [31:0] CARD_VERSION = 32'd0,
    parameter [31:0] CARD_BUILD = 32'd0,
    parameter [31:0] PCI_ID = 32'h903410EE,
    parameter [31:0] PCI_CLASS = 32'h05800000,
    parameter [31:0] PCI_SUBSYS = 32'h000710EE
) (
    input  wire        clk50,
    input  wire        c0_sys_clk_p,
    input  wire        c0_sys_clk_n,
    output wire [16:0] c0_ddr4_adr,
    output wire [1:0]  c0_ddr4_ba,
    output wire [0:0]  c0_ddr4_bg,
    output wire [0:0]  c0_ddr4_cke,
    output wire [0:0]  c0_ddr4_odt,
    output wire [0:0]  c0_ddr4_cs_n,
    output wire [0:0]  c0_ddr4_ck_t,
    output wire [0:0]  c0_ddr4_ck_c,
    output wire        c0_ddr4_act_n,
    output wire        c0_ddr4_par,
    output wire        c0_ddr4_reset_n,
    inout  wire [3:0]  c0_ddr4_dm_dbi_n,
    inout  wire [31:0] c0_ddr4_dq,
    inout  wire [3:0]  c0_ddr4_dqs_t,
    inout  wire [3:0]  c0_ddr4_dqs_c,
    input  wire        key_rst,
    output wire [7:0]  led,
    input  wire        uart2_rx,
    output wire        uart2_tx,
    input  wire        pcie_refclk_p,
    input  wire        pcie_refclk_n,
    input  wire        pcie_perst_n,
    output wire [3:0]  pcie_txp,
    output wire [3:0]  pcie_txn,
    input  wire [3:0]  pcie_rxp,
    input  wire [3:0]  pcie_rxn
);
    // ---------------------------------------------------------------- clocks and resets
    wire clk50_ibuf, mmcm_fb, mmcm_locked, per_clk_raw, per_clk;
    wire ui_clk, ui_rst, calib;
    wire cpu_clk = ui_clk;

    IBUF u_clk50_ibuf (.I(clk50), .O(clk50_ibuf));
    MMCME4_ADV #(
        .CLKIN1_PERIOD(20.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(20.0),   // 1000 MHz VCO
        .CLKOUT0_DIVIDE_F(10.0)   // 100 MHz
    ) u_mmcm (
        .CLKIN1(clk50_ibuf), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb),
        .CLKOUT0(per_clk_raw),
        .LOCKED(mmcm_locked), .RST(1'b0), .PWRDWN(1'b0),
        .DADDR(7'd0), .DCLK(1'b0), .DEN(1'b0), .DI(16'd0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0));
    BUFG u_bufg_per (.I(per_clk_raw), .O(per_clk));

    reg [2:0] cpu_rst_q = 3'b000;
    reg [2:0] per_rst_q = 3'b000;
    always @(posedge cpu_clk or negedge calib)
        if (!calib) cpu_rst_q <= 3'b000;
        else cpu_rst_q <= {cpu_rst_q[1:0], 1'b1};
    always @(posedge per_clk or negedge mmcm_locked)
        if (!mmcm_locked) per_rst_q <= 3'b000;
        else per_rst_q <= {per_rst_q[1:0], 1'b1};
    wire cpu_rst_n = cpu_rst_q[2];
    wire per_rst_n = per_rst_q[2];
    wire cpu_reset = ~cpu_rst_n;
    wire ui_rst_n = ~ui_rst;

    // ---------------------------------------------------------------- bus masters: the UART rig (nocpu_core) and the PCIe DMA path
    wire        m_awvalid, m_awready, m_wvalid, m_wready, m_wlast, m_bvalid, m_bready;
    wire        m_arvalid, m_arready, m_rvalid, m_rready, m_rlast;
    wire [31:0] m_awaddr, m_araddr;
    wire [7:0]  m_awid, m_arid, m_awlen, m_arlen, m_bid, m_rid;
    wire [2:0]  m_awsize, m_arsize;
    wire [1:0]  m_awburst, m_arburst, m_bresp, m_rresp;
    wire [255:0] m_wdata, m_rdata;
    wire [31:0] m_wstrb;

    wire        p_awvalid, p_awready, p_wvalid, p_wready, p_bvalid, p_bready;
    wire        p_arvalid, p_arready, p_rvalid, p_rready;
    wire [31:0] p_awaddr, p_araddr, p_wdata, p_rdata;
    wire [2:0]  p_awprot, p_arprot;
    wire [3:0]  p_wstrb;
    wire [1:0]  p_bresp, p_rresp;

    wire        dma_awvalid, dma_awready, dma_wvalid, dma_wready, dma_wlast, dma_bvalid, dma_bready, dma_arready, dma_rvalid, dma_rlast;
    wire [31:0] dma_awaddr, dma_araddr;
    wire [7:0]  dma_awlen, dma_wstrb, dma_arlen;
    wire [2:0]  dma_awsize, dma_arsize;
    wire [1:0]  dma_awburst, dma_arburst, dma_bresp, dma_rresp;
    wire [63:0] dma_wdata, dma_rdata;
    wire        dma_arvalid, dma_rready;
    wire [3:0]  dma_bid, dma_rid, dma_awid, dma_arid;

    wire pcie_irq, pcie_irq_s;
    // the rig reads the interrupt vector (`I`): bit 9 = the PCIe host doorbell, as in the CPU builds
    irq_sync #(.W(1)) u_irq_sync (.clk(cpu_clk), .d(pcie_irq), .q(pcie_irq_s));

    nocpu_core u_soc (
        .litex_clk(cpu_clk),
        .litex_reset(cpu_reset),
        .peripheral_externalInterrupts_port({22'd0, pcie_irq_s, 9'd0}),
        .uart2_rx(uart2_rx), .uart2_tx(uart2_tx),
        .mBus_awvalid(m_awvalid), .mBus_awready(m_awready), .mBus_awaddr(m_awaddr), .mBus_awid(m_awid),
        .mBus_awlen(m_awlen), .mBus_awsize(m_awsize), .mBus_awburst(m_awburst),
        .mBus_wvalid(m_wvalid), .mBus_wready(m_wready), .mBus_wdata(m_wdata), .mBus_wstrb(m_wstrb), .mBus_wlast(m_wlast),
        .mBus_bvalid(m_bvalid), .mBus_bready(m_bready), .mBus_bid(m_bid), .mBus_bresp(m_bresp),
        .mBus_arvalid(m_arvalid), .mBus_arready(m_arready), .mBus_araddr(m_araddr), .mBus_arid(m_arid),
        .mBus_arlen(m_arlen), .mBus_arsize(m_arsize), .mBus_arburst(m_arburst),
        .mBus_rvalid(m_rvalid), .mBus_rready(m_rready), .mBus_rdata(m_rdata), .mBus_rid(m_rid),
        .mBus_rresp(m_rresp), .mBus_rlast(m_rlast),
        .pBus_awvalid(p_awvalid), .pBus_awready(p_awready), .pBus_awaddr(p_awaddr), .pBus_awprot(p_awprot),
        .pBus_wvalid(p_wvalid), .pBus_wready(p_wready), .pBus_wdata(p_wdata), .pBus_wstrb(p_wstrb),
        .pBus_bvalid(p_bvalid), .pBus_bready(p_bready), .pBus_bresp(p_bresp),
        .pBus_arvalid(p_arvalid), .pBus_arready(p_arready), .pBus_araddr(p_araddr), .pBus_arprot(p_arprot),
        .pBus_rvalid(p_rvalid), .pBus_rready(p_rready), .pBus_rdata(p_rdata), .pBus_rresp(p_rresp),
        .dma_bus_awvalid(dma_awvalid), .dma_bus_awready(dma_awready), .dma_bus_awaddr(dma_awaddr), .dma_bus_awid(dma_awid),
        .dma_bus_awlen(dma_awlen), .dma_bus_awsize(dma_awsize), .dma_bus_awburst(dma_awburst),
        .dma_bus_wvalid(dma_wvalid), .dma_bus_wready(dma_wready), .dma_bus_wdata(dma_wdata), .dma_bus_wstrb(dma_wstrb), .dma_bus_wlast(dma_wlast),
        .dma_bus_bvalid(dma_bvalid), .dma_bus_bready(dma_bready), .dma_bus_bid(dma_bid), .dma_bus_bresp(dma_bresp),
        .dma_bus_arvalid(dma_arvalid), .dma_bus_arready(dma_arready), .dma_bus_araddr(dma_araddr), .dma_bus_arid(dma_arid),
        .dma_bus_arlen(dma_arlen), .dma_bus_arsize(dma_arsize), .dma_bus_arburst(dma_arburst),
        .dma_bus_rvalid(dma_rvalid), .dma_bus_rready(dma_rready), .dma_bus_rdata(dma_rdata), .dma_bus_rid(dma_rid),
        .dma_bus_rresp(dma_rresp), .dma_bus_rlast(dma_rlast));

    // ---------------------------------------------------------------- memory path: DDR4 controller (256-bit AXI4 at ui_clk)
    assign c0_ddr4_par = 1'b0;   // CA parity is disabled in the controller; DDR4 needs a valid level on PAR
    wire [29:0] d_awaddr = m_awaddr[29:0];
    wire [29:0] d_araddr = m_araddr[29:0];
    ddr4_0 u_ddr4 (
        .c0_init_calib_complete(calib),
        .dbg_clk(),
        .c0_sys_clk_p(c0_sys_clk_p),
        .c0_sys_clk_n(c0_sys_clk_n),
        .dbg_bus(),
        .c0_ddr4_adr(c0_ddr4_adr),
        .c0_ddr4_ba(c0_ddr4_ba),
        .c0_ddr4_cke(c0_ddr4_cke),
        .c0_ddr4_cs_n(c0_ddr4_cs_n),
        .c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq(c0_ddr4_dq),
        .c0_ddr4_dqs_c(c0_ddr4_dqs_c),
        .c0_ddr4_dqs_t(c0_ddr4_dqs_t),
        .c0_ddr4_odt(c0_ddr4_odt),
        .c0_ddr4_bg(c0_ddr4_bg),
        .c0_ddr4_reset_n(c0_ddr4_reset_n),
        .c0_ddr4_act_n(c0_ddr4_act_n),
        .c0_ddr4_ck_c(c0_ddr4_ck_c),
        .c0_ddr4_ck_t(c0_ddr4_ck_t),
        .c0_ddr4_ui_clk(ui_clk),
        .c0_ddr4_ui_clk_sync_rst(ui_rst),
        .c0_ddr4_aresetn(ui_rst_n),
        .c0_ddr4_s_axi_awid(m_awid),
        .c0_ddr4_s_axi_awaddr(d_awaddr),
        .c0_ddr4_s_axi_awlen(m_awlen),
        .c0_ddr4_s_axi_awsize(m_awsize),
        .c0_ddr4_s_axi_awburst(m_awburst),
        .c0_ddr4_s_axi_awlock(1'b0),
        .c0_ddr4_s_axi_awcache(4'd0),
        .c0_ddr4_s_axi_awprot(3'd0),
        .c0_ddr4_s_axi_awqos(4'd0),
        .c0_ddr4_s_axi_awvalid(m_awvalid),
        .c0_ddr4_s_axi_awready(m_awready),
        .c0_ddr4_s_axi_wdata(m_wdata),
        .c0_ddr4_s_axi_wstrb(m_wstrb),
        .c0_ddr4_s_axi_wlast(m_wlast),
        .c0_ddr4_s_axi_wvalid(m_wvalid),
        .c0_ddr4_s_axi_wready(m_wready),
        .c0_ddr4_s_axi_bready(m_bready),
        .c0_ddr4_s_axi_bid(m_bid),
        .c0_ddr4_s_axi_bresp(m_bresp),
        .c0_ddr4_s_axi_bvalid(m_bvalid),
        .c0_ddr4_s_axi_arid(m_arid),
        .c0_ddr4_s_axi_araddr(d_araddr),
        .c0_ddr4_s_axi_arlen(m_arlen),
        .c0_ddr4_s_axi_arsize(m_arsize),
        .c0_ddr4_s_axi_arburst(m_arburst),
        .c0_ddr4_s_axi_arlock(1'b0),
        .c0_ddr4_s_axi_arcache(4'd0),
        .c0_ddr4_s_axi_arprot(3'd0),
        .c0_ddr4_s_axi_arqos(4'd0),
        .c0_ddr4_s_axi_arvalid(m_arvalid),
        .c0_ddr4_s_axi_arready(m_arready),
        .c0_ddr4_s_axi_rready(m_rready),
        .c0_ddr4_s_axi_rlast(m_rlast),
        .c0_ddr4_s_axi_rvalid(m_rvalid),
        .c0_ddr4_s_axi_rresp(m_rresp),
        .c0_ddr4_s_axi_rid(m_rid),
        .c0_ddr4_s_axi_rdata(m_rdata),
        .sys_rst(key_rst));

    // ---------------------------------------------------------------- register path: rig (cpu_clk) -> cc_per -> crossbar (per_clk); the host's BAR0 is the second master
    wire        q_awvalid, q_awready, q_wvalid, q_wready, q_bvalid, q_bready;
    wire        q_arvalid, q_arready, q_rvalid, q_rready;
    wire [31:0] q_awaddr, q_araddr, q_wdata, q_rdata;
    wire [2:0]  q_awprot, q_arprot;
    wire [3:0]  q_wstrb;
    wire [1:0]  q_bresp, q_rresp;

    cc_per u_cc_per (
        .s_axi_aclk(cpu_clk), .s_axi_aresetn(cpu_rst_n),
        .s_axi_awaddr(p_awaddr), .s_axi_awprot(p_awprot), .s_axi_awvalid(p_awvalid), .s_axi_awready(p_awready),
        .s_axi_wdata(p_wdata), .s_axi_wstrb(p_wstrb), .s_axi_wvalid(p_wvalid), .s_axi_wready(p_wready),
        .s_axi_bresp(p_bresp), .s_axi_bvalid(p_bvalid), .s_axi_bready(p_bready),
        .s_axi_araddr(p_araddr), .s_axi_arprot(p_arprot), .s_axi_arvalid(p_arvalid), .s_axi_arready(p_arready),
        .s_axi_rdata(p_rdata), .s_axi_rresp(p_rresp), .s_axi_rvalid(p_rvalid), .s_axi_rready(p_rready),
        .m_axi_aclk(per_clk), .m_axi_aresetn(per_rst_n),
        .m_axi_awaddr(q_awaddr), .m_axi_awprot(q_awprot), .m_axi_awvalid(q_awvalid), .m_axi_awready(q_awready),
        .m_axi_wdata(q_wdata), .m_axi_wstrb(q_wstrb), .m_axi_wvalid(q_wvalid), .m_axi_wready(q_wready),
        .m_axi_bresp(q_bresp), .m_axi_bvalid(q_bvalid), .m_axi_bready(q_bready),
        .m_axi_araddr(q_araddr), .m_axi_arprot(q_arprot), .m_axi_arvalid(q_arvalid), .m_axi_arready(q_arready),
        .m_axi_rdata(q_rdata), .m_axi_rresp(q_rresp), .m_axi_rvalid(q_rvalid), .m_axi_rready(q_rready));

    wire [15:0] hl_awaddr, hl_araddr;
    wire [31:0] hl_wdata, hl_rdata;
    wire [3:0]  hl_wstrb;
    wire [1:0]  hl_bresp, hl_rresp;
    wire        hl_awvalid, hl_awready, hl_wvalid, hl_wready, hl_bvalid, hl_bready, hl_arvalid, hl_arready, hl_rvalid, hl_rready;

    // crossbar slaves: 0 card_regs 0xF8001000, 1 user_regs 0xF8002000, 2 pcie_regs 0xF800A000 (4 KiB each); SI0 = rig, SI1 = host BAR0
    wire [95:0] x_awaddr, x_araddr, x_wdata, x_rdata;
    wire [8:0]  x_awprot, x_arprot;
    wire [11:0] x_wstrb;
    wire [5:0]  x_bresp, x_rresp;
    wire [2:0]  x_awvalid, x_awready, x_wvalid, x_wready, x_bvalid, x_bready;
    wire [2:0]  x_arvalid, x_arready, x_rvalid, x_rready;
    wire [1:0]  xs_awready, xs_wready, xs_bvalid, xs_arready, xs_rvalid;
    wire [3:0]  xs_bresp, xs_rresp;
    wire [63:0] xs_rdata;

    xbar_card u_xbar (
        .aclk(per_clk), .aresetn(per_rst_n),
        .s_axi_awaddr({16'hF800, hl_awaddr, q_awaddr}), .s_axi_awprot({3'd0, q_awprot}), .s_axi_awvalid({hl_awvalid, q_awvalid}), .s_axi_awready(xs_awready),
        .s_axi_wdata({hl_wdata, q_wdata}), .s_axi_wstrb({hl_wstrb, q_wstrb}), .s_axi_wvalid({hl_wvalid, q_wvalid}), .s_axi_wready(xs_wready),
        .s_axi_bresp(xs_bresp), .s_axi_bvalid(xs_bvalid), .s_axi_bready({hl_bready, q_bready}),
        .s_axi_araddr({16'hF800, hl_araddr, q_araddr}), .s_axi_arprot({3'd0, q_arprot}), .s_axi_arvalid({hl_arvalid, q_arvalid}), .s_axi_arready(xs_arready),
        .s_axi_rdata(xs_rdata), .s_axi_rresp(xs_rresp), .s_axi_rvalid(xs_rvalid), .s_axi_rready({hl_rready, q_rready}),
        .m_axi_awaddr(x_awaddr), .m_axi_awprot(x_awprot), .m_axi_awvalid(x_awvalid), .m_axi_awready(x_awready),
        .m_axi_wdata(x_wdata), .m_axi_wstrb(x_wstrb), .m_axi_wvalid(x_wvalid), .m_axi_wready(x_wready),
        .m_axi_bresp(x_bresp), .m_axi_bvalid(x_bvalid), .m_axi_bready(x_bready),
        .m_axi_araddr(x_araddr), .m_axi_arprot(x_arprot), .m_axi_arvalid(x_arvalid), .m_axi_arready(x_arready),
        .m_axi_rdata(x_rdata), .m_axi_rresp(x_rresp), .m_axi_rvalid(x_rvalid), .m_axi_rready(x_rready));

    assign q_awready = xs_awready[0];
    assign q_wready = xs_wready[0];
    assign q_bresp = xs_bresp[1:0];
    assign q_bvalid = xs_bvalid[0];
    assign q_arready = xs_arready[0];
    assign q_rdata = xs_rdata[31:0];
    assign q_rresp = xs_rresp[1:0];
    assign q_rvalid = xs_rvalid[0];
    assign hl_awready = xs_awready[1];
    assign hl_wready = xs_wready[1];
    assign hl_bresp = xs_bresp[3:2];
    assign hl_bvalid = xs_bvalid[1];
    assign hl_arready = xs_arready[1];
    assign hl_rdata = xs_rdata[63:32];
    assign hl_rresp = xs_rresp[3:2];
    assign hl_rvalid = xs_rvalid[1];

    // ---------------------------------------------------------------- register blocks
    wire [7:0] reg_led;
    assign led = reg_led;
    card_regs #(.VERSION(CARD_VERSION), .BUILD(CARD_BUILD), .PCI_ID(PCI_ID), .PCI_CLASS(PCI_CLASS), .PCI_SUBSYS(PCI_SUBSYS), .DDR_MIB(32'd1024)) u_cregs (
        .clk(per_clk), .rst_n(per_rst_n),
        .s_awaddr(x_awaddr[11:0]), .s_awvalid(x_awvalid[0]), .s_awready(x_awready[0]),
        .s_wdata(x_wdata[31:0]), .s_wstrb(x_wstrb[3:0]), .s_wvalid(x_wvalid[0]), .s_wready(x_wready[0]),
        .s_bresp(x_bresp[1:0]), .s_bvalid(x_bvalid[0]), .s_bready(x_bready[0]),
        .s_araddr(x_araddr[11:0]), .s_arvalid(x_arvalid[0]), .s_arready(x_arready[0]),
        .s_rdata(x_rdata[31:0]), .s_rresp(x_rresp[1:0]), .s_rvalid(x_rvalid[0]), .s_rready(x_rready[0]),
        .calib_in(calib), .key_in(key_rst), .led(reg_led));

    // Hook for future firmware functions: `user_ctl` and `user_kick` are the outputs, `user_sts` and `user_event` the inputs of whatever block attaches here.
    wire [511:0] user_ctl;
    wire [31:0]  user_kick;
    wire         user_irq;
    user_regs u_uregs (
        .clk(per_clk), .rst_n(per_rst_n),
        .s_awaddr(x_awaddr[43:32]), .s_awvalid(x_awvalid[1]), .s_awready(x_awready[1]),
        .s_wdata(x_wdata[63:32]), .s_wstrb(x_wstrb[7:4]), .s_wvalid(x_wvalid[1]), .s_wready(x_wready[1]),
        .s_bresp(x_bresp[3:2]), .s_bvalid(x_bvalid[1]), .s_bready(x_bready[1]),
        .s_araddr(x_araddr[43:32]), .s_arvalid(x_arvalid[1]), .s_arready(x_arready[1]),
        .s_rdata(x_rdata[63:32]), .s_rresp(x_rresp[3:2]), .s_rvalid(x_rvalid[1]), .s_rready(x_rready[1]),
        .ctl(user_ctl), .sts(512'd0), .kick(user_kick), .event_in(32'd0), .irq(user_irq));

    // ---------------------------------------------------------------- PCIe endpoint: the XDMA master goes straight to the hub DMA port of nocpu_core
    pcie_ep u_pcie (
        .sys_clk_p(pcie_refclk_p), .sys_clk_n(pcie_refclk_n), .sys_rst_n(pcie_perst_n),
        .pci_exp_txp(pcie_txp), .pci_exp_txn(pcie_txn), .pci_exp_rxp(pcie_rxp), .pci_exp_rxn(pcie_rxn),
        .clk(cpu_clk), .rst_n(cpu_rst_n), .per_clk(per_clk), .per_rst_n(per_rst_n),
        .m_awid(dma_awid), .m_awaddr(dma_awaddr), .m_awlen(dma_awlen), .m_awsize(dma_awsize), .m_awburst(dma_awburst), .m_awvalid(dma_awvalid),
        .m_awready(dma_awready), .m_wdata(dma_wdata), .m_wstrb(dma_wstrb), .m_wlast(dma_wlast), .m_wvalid(dma_wvalid), .m_wready(dma_wready),
        .m_bid(dma_bid), .m_bresp(dma_bresp), .m_bvalid(dma_bvalid), .m_bready(dma_bready),
        .m_arid(dma_arid), .m_araddr(dma_araddr), .m_arlen(dma_arlen), .m_arsize(dma_arsize), .m_arburst(dma_arburst), .m_arvalid(dma_arvalid),
        .m_arready(dma_arready), .m_rid(dma_rid), .m_rdata(dma_rdata), .m_rresp(dma_rresp), .m_rlast(dma_rlast), .m_rvalid(dma_rvalid),
        .m_rready(dma_rready),
        .c_awaddr(x_awaddr[70:64]), .c_awvalid(x_awvalid[2]), .c_awready(x_awready[2]),
        .c_wdata(x_wdata[95:64]), .c_wstrb(x_wstrb[11:8]), .c_wvalid(x_wvalid[2]), .c_wready(x_wready[2]),
        .c_bresp(x_bresp[5:4]), .c_bvalid(x_bvalid[2]), .c_bready(x_bready[2]),
        .c_araddr(x_araddr[70:64]), .c_arvalid(x_arvalid[2]), .c_arready(x_arready[2]),
        .c_rdata(x_rdata[95:64]), .c_rresp(x_rresp[5:4]), .c_rvalid(x_rvalid[2]), .c_rready(x_rready[2]),
        .hl_awaddr(hl_awaddr), .hl_awvalid(hl_awvalid), .hl_awready(hl_awready), .hl_wdata(hl_wdata), .hl_wstrb(hl_wstrb), .hl_wvalid(hl_wvalid),
        .hl_wready(hl_wready), .hl_bresp(hl_bresp), .hl_bvalid(hl_bvalid), .hl_bready(hl_bready),
        .hl_araddr(hl_araddr), .hl_arvalid(hl_arvalid), .hl_arready(hl_arready), .hl_rdata(hl_rdata), .hl_rresp(hl_rresp), .hl_rvalid(hl_rvalid),
        .hl_rready(hl_rready),
        .irq(pcie_irq));

    // user_ctl, user_kick and user_irq have no consumer yet
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_user = ^user_ctl ^ ^user_kick ^ user_irq;
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
