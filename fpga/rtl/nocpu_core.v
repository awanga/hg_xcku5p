// SPDX-License-Identifier: MIT
// CPU-less stand-in for the VexiiRiscv SoC netlist (decision 0008, variant 3): same bus ports, no processor. The UART test rig (uart_rig, UART2) is the
// only master of the peripheral port (pBus, AXI4-Lite); memory (mBus, the DDR4 controller's 256-bit AXI4 port) is shared by the rig and the hub DMA
// port (dma_bus, 64-bit, eth_dma, HDMI and PCIe masters) through a 64->256 width converter and a 2-slave crossbar. Needs the IPs nc_dw (axi_dwidth_converter
// 64->256, ids 4 bits) and nc_xbar (axi_crossbar, 2 slaves of 256 bit, 1-bit ids, one master over the whole address space), created by build_soc.tcl -nocpu.
// Interrupts are not used by a CPU: the vector is readable with the rig's `I` command.
module nocpu_core (
    input  wire         litex_clk,
    input  wire         litex_reset,
    input  wire [31:0]  peripheral_externalInterrupts_port,
    input  wire         uart2_rx,
    output wire         uart2_tx,
    // memory master (DDR4 controller)
    output wire         mBus_awvalid,
    input  wire         mBus_awready,
    output wire [31:0]  mBus_awaddr,
    output wire [7:0]   mBus_awid,
    output wire [7:0]   mBus_awlen,
    output wire [2:0]   mBus_awsize,
    output wire [1:0]   mBus_awburst,
    output wire         mBus_wvalid,
    input  wire         mBus_wready,
    output wire [255:0] mBus_wdata,
    output wire [31:0]  mBus_wstrb,
    output wire         mBus_wlast,
    input  wire         mBus_bvalid,
    output wire         mBus_bready,
    input  wire [7:0]   mBus_bid,
    input  wire [1:0]   mBus_bresp,
    output wire         mBus_arvalid,
    input  wire         mBus_arready,
    output wire [31:0]  mBus_araddr,
    output wire [7:0]   mBus_arid,
    output wire [7:0]   mBus_arlen,
    output wire [2:0]   mBus_arsize,
    output wire [1:0]   mBus_arburst,
    input  wire         mBus_rvalid,
    output wire         mBus_rready,
    input  wire [255:0] mBus_rdata,
    input  wire [7:0]   mBus_rid,
    input  wire [1:0]   mBus_rresp,
    input  wire         mBus_rlast,
    // peripheral master
    output wire         pBus_awvalid,
    input  wire         pBus_awready,
    output wire [31:0]  pBus_awaddr,
    output wire [2:0]   pBus_awprot,
    output wire         pBus_wvalid,
    input  wire         pBus_wready,
    output wire [31:0]  pBus_wdata,
    output wire [3:0]   pBus_wstrb,
    input  wire         pBus_bvalid,
    output wire         pBus_bready,
    input  wire [1:0]   pBus_bresp,
    output wire         pBus_arvalid,
    input  wire         pBus_arready,
    output wire [31:0]  pBus_araddr,
    output wire [2:0]   pBus_arprot,
    input  wire         pBus_rvalid,
    output wire         pBus_rready,
    input  wire [31:0]  pBus_rdata,
    input  wire [1:0]   pBus_rresp,
    // hub DMA slave (64-bit)
    input  wire         dma_bus_awvalid,
    output wire         dma_bus_awready,
    input  wire [31:0]  dma_bus_awaddr,
    input  wire [3:0]   dma_bus_awid,
    input  wire [7:0]   dma_bus_awlen,
    input  wire [2:0]   dma_bus_awsize,
    input  wire [1:0]   dma_bus_awburst,
    input  wire         dma_bus_wvalid,
    output wire         dma_bus_wready,
    input  wire [63:0]  dma_bus_wdata,
    input  wire [7:0]   dma_bus_wstrb,
    input  wire         dma_bus_wlast,
    output wire         dma_bus_bvalid,
    input  wire         dma_bus_bready,
    output wire [3:0]   dma_bus_bid,
    output wire [1:0]   dma_bus_bresp,
    input  wire         dma_bus_arvalid,
    output wire         dma_bus_arready,
    input  wire [31:0]  dma_bus_araddr,
    input  wire [3:0]   dma_bus_arid,
    input  wire [7:0]   dma_bus_arlen,
    input  wire [2:0]   dma_bus_arsize,
    input  wire [1:0]   dma_bus_arburst,
    output wire         dma_bus_rvalid,
    input  wire         dma_bus_rready,
    output wire [63:0]  dma_bus_rdata,
    output wire [3:0]   dma_bus_rid,
    output wire [1:0]   dma_bus_rresp,
    output wire         dma_bus_rlast
);
    wire rst_n = ~litex_reset;

    // ---------------------------------------------------------------- UART rig: peripheral port and memory port 0
    wire        r_awvalid, r_awready, r_wvalid, r_wready, r_wlast, r_bvalid, r_bready, r_arvalid, r_arready, r_rvalid, r_rready;
    wire [31:0] r_awaddr, r_araddr, r_wstrb;
    wire [7:0]  r_awlen, r_arlen;
    wire [2:0]  r_awsize, r_arsize;
    wire [1:0]  r_awburst, r_arburst, r_bresp, r_rresp;
    wire [255:0] r_wdata, r_rdata;
    uart_rig u_rig (
        .clk(litex_clk), .rst_n(rst_n), .rx(uart2_rx), .tx(uart2_tx), .irq_in(peripheral_externalInterrupts_port),
        .p_awaddr(pBus_awaddr), .p_awprot(pBus_awprot), .p_awvalid(pBus_awvalid), .p_awready(pBus_awready), .p_wdata(pBus_wdata), .p_wstrb(pBus_wstrb),
        .p_wvalid(pBus_wvalid), .p_wready(pBus_wready), .p_bresp(pBus_bresp), .p_bvalid(pBus_bvalid), .p_bready(pBus_bready),
        .p_araddr(pBus_araddr), .p_arprot(pBus_arprot), .p_arvalid(pBus_arvalid), .p_arready(pBus_arready), .p_rdata(pBus_rdata),
        .p_rresp(pBus_rresp), .p_rvalid(pBus_rvalid), .p_rready(pBus_rready),
        .m_awaddr(r_awaddr), .m_awlen(r_awlen), .m_awsize(r_awsize), .m_awburst(r_awburst), .m_awvalid(r_awvalid), .m_awready(r_awready),
        .m_wdata(r_wdata), .m_wstrb(r_wstrb), .m_wlast(r_wlast), .m_wvalid(r_wvalid), .m_wready(r_wready),
        .m_bresp(r_bresp), .m_bvalid(r_bvalid), .m_bready(r_bready),
        .m_araddr(r_araddr), .m_arlen(r_arlen), .m_arsize(r_arsize), .m_arburst(r_arburst), .m_arvalid(r_arvalid), .m_arready(r_arready),
        .m_rdata(r_rdata), .m_rresp(r_rresp), .m_rvalid(r_rvalid), .m_rready(r_rready));

    // ---------------------------------------------------------------- hub DMA port: 64 -> 256 bit, memory port 1
    wire        d_awvalid, d_awready, d_wvalid, d_wready, d_wlast, d_bvalid, d_bready, d_arvalid, d_arready, d_rvalid, d_rready, d_rlast;
    wire [31:0] d_awaddr, d_araddr, d_wstrb;
    wire [7:0]  d_awlen, d_arlen;
    wire [2:0]  d_awsize, d_arsize;
    wire [1:0]  d_awburst, d_arburst, d_bresp, d_rresp;
    wire [255:0] d_wdata, d_rdata;
    nc_dw u_dw (
        .s_axi_aclk(litex_clk), .s_axi_aresetn(rst_n),
        .s_axi_awid(dma_bus_awid), .s_axi_awaddr(dma_bus_awaddr), .s_axi_awlen(dma_bus_awlen), .s_axi_awsize(dma_bus_awsize),
        .s_axi_awburst(dma_bus_awburst), .s_axi_awlock(1'b0), .s_axi_awcache(4'd0), .s_axi_awprot(3'd0), .s_axi_awregion(4'd0), .s_axi_awqos(4'd0),
        .s_axi_awvalid(dma_bus_awvalid), .s_axi_awready(dma_bus_awready),
        .s_axi_wdata(dma_bus_wdata), .s_axi_wstrb(dma_bus_wstrb), .s_axi_wlast(dma_bus_wlast), .s_axi_wvalid(dma_bus_wvalid), .s_axi_wready(dma_bus_wready),
        .s_axi_bid(dma_bus_bid), .s_axi_bresp(dma_bus_bresp), .s_axi_bvalid(dma_bus_bvalid), .s_axi_bready(dma_bus_bready),
        .s_axi_arid(dma_bus_arid), .s_axi_araddr(dma_bus_araddr), .s_axi_arlen(dma_bus_arlen), .s_axi_arsize(dma_bus_arsize),
        .s_axi_arburst(dma_bus_arburst), .s_axi_arlock(1'b0), .s_axi_arcache(4'd0), .s_axi_arprot(3'd0), .s_axi_arregion(4'd0), .s_axi_arqos(4'd0),
        .s_axi_arvalid(dma_bus_arvalid), .s_axi_arready(dma_bus_arready),
        .s_axi_rid(dma_bus_rid), .s_axi_rdata(dma_bus_rdata), .s_axi_rresp(dma_bus_rresp), .s_axi_rlast(dma_bus_rlast),
        .s_axi_rvalid(dma_bus_rvalid), .s_axi_rready(dma_bus_rready),
        .m_axi_awaddr(d_awaddr), .m_axi_awlen(d_awlen), .m_axi_awsize(d_awsize), .m_axi_awburst(d_awburst),
        .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(), .m_axi_awregion(), .m_axi_awqos(),
        .m_axi_awvalid(d_awvalid), .m_axi_awready(d_awready),
        .m_axi_wdata(d_wdata), .m_axi_wstrb(d_wstrb), .m_axi_wlast(d_wlast), .m_axi_wvalid(d_wvalid), .m_axi_wready(d_wready),
        .m_axi_bresp(d_bresp), .m_axi_bvalid(d_bvalid), .m_axi_bready(d_bready),
        .m_axi_araddr(d_araddr), .m_axi_arlen(d_arlen), .m_axi_arsize(d_arsize), .m_axi_arburst(d_arburst),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arregion(), .m_axi_arqos(),
        .m_axi_arvalid(d_arvalid), .m_axi_arready(d_arready),
        .m_axi_rdata(d_rdata), .m_axi_rresp(d_rresp), .m_axi_rlast(d_rlast), .m_axi_rvalid(d_rvalid), .m_axi_rready(d_rready));

    // ---------------------------------------------------------------- memory crossbar: SI0 rig, SI1 hub DMA port -> DDR4 controller
    wire [1:0]  x_awready, x_wready, x_bvalid, x_arready, x_rvalid, x_rlast;
    wire [3:0]  x_bresp, x_rresp;
    wire [1:0]  x_bid, x_rid;
    wire [511:0] x_rdata;
    nc_xbar u_xbar (
        .aclk(litex_clk), .aresetn(rst_n),
        .s_axi_awid(2'b00), .s_axi_awaddr({d_awaddr, r_awaddr}), .s_axi_awlen({d_awlen, r_awlen}), .s_axi_awsize({d_awsize, r_awsize}),
        .s_axi_awburst({d_awburst, r_awburst}), .s_axi_awlock(2'b00), .s_axi_awcache(8'd0), .s_axi_awprot(6'd0), .s_axi_awqos(8'd0),
        .s_axi_awvalid({d_awvalid, r_awvalid}), .s_axi_awready(x_awready),
        .s_axi_wdata({d_wdata, r_wdata}), .s_axi_wstrb({d_wstrb, r_wstrb}), .s_axi_wlast({d_wlast, r_wlast}),
        .s_axi_wvalid({d_wvalid, r_wvalid}), .s_axi_wready(x_wready),
        .s_axi_bid(x_bid), .s_axi_bresp(x_bresp), .s_axi_bvalid(x_bvalid), .s_axi_bready({d_bready, r_bready}),
        .s_axi_arid(2'b00), .s_axi_araddr({d_araddr, r_araddr}), .s_axi_arlen({d_arlen, r_arlen}), .s_axi_arsize({d_arsize, r_arsize}),
        .s_axi_arburst({d_arburst, r_arburst}), .s_axi_arlock(2'b00), .s_axi_arcache(8'd0), .s_axi_arprot(6'd0), .s_axi_arqos(8'd0),
        .s_axi_arvalid({d_arvalid, r_arvalid}), .s_axi_arready(x_arready),
        .s_axi_rid(x_rid), .s_axi_rdata(x_rdata), .s_axi_rresp(x_rresp), .s_axi_rlast(x_rlast), .s_axi_rvalid(x_rvalid),
        .s_axi_rready({d_rready, r_rready}),
        .m_axi_awid(mBus_awid[1:0]), .m_axi_awaddr(mBus_awaddr), .m_axi_awlen(mBus_awlen), .m_axi_awsize(mBus_awsize), .m_axi_awburst(mBus_awburst),
        .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(), .m_axi_awqos(), .m_axi_awvalid(mBus_awvalid), .m_axi_awready(mBus_awready),
        .m_axi_wdata(mBus_wdata), .m_axi_wstrb(mBus_wstrb), .m_axi_wlast(mBus_wlast), .m_axi_wvalid(mBus_wvalid), .m_axi_wready(mBus_wready),
        .m_axi_bid(mBus_bid[1:0]), .m_axi_bresp(mBus_bresp), .m_axi_bvalid(mBus_bvalid), .m_axi_bready(mBus_bready),
        .m_axi_arid(mBus_arid[1:0]), .m_axi_araddr(mBus_araddr), .m_axi_arlen(mBus_arlen), .m_axi_arsize(mBus_arsize), .m_axi_arburst(mBus_arburst),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arqos(), .m_axi_arvalid(mBus_arvalid), .m_axi_arready(mBus_arready),
        .m_axi_rid(mBus_rid[1:0]), .m_axi_rdata(mBus_rdata), .m_axi_rresp(mBus_rresp), .m_axi_rlast(mBus_rlast), .m_axi_rvalid(mBus_rvalid),
        .m_axi_rready(mBus_rready));
    assign mBus_awid[7:2] = 6'd0;
    assign mBus_arid[7:2] = 6'd0;
    assign r_awready = x_awready[0];
    assign d_awready = x_awready[1];
    assign r_wready = x_wready[0];
    assign d_wready = x_wready[1];
    assign r_bvalid = x_bvalid[0];
    assign d_bvalid = x_bvalid[1];
    assign r_bresp = x_bresp[1:0];
    assign d_bresp = x_bresp[3:2];
    assign r_arready = x_arready[0];
    assign d_arready = x_arready[1];
    assign r_rvalid = x_rvalid[0];
    assign d_rvalid = x_rvalid[1];
    assign r_rdata = x_rdata[255:0];
    assign d_rdata = x_rdata[511:256];
    assign r_rresp = x_rresp[1:0];
    assign d_rresp = x_rresp[3:2];
    assign d_rlast = x_rlast[1];
    // ids that are only returned, never used by the rig and the converter
    wire unused = &{1'b0, x_bid, x_rid, mBus_bid[7:2], mBus_rid[7:2], x_rlast[0]};
endmodule
