// SPDX-License-Identifier: MIT
// Reference function block of the CPU-less PCIe card (card_top): the place to attach a new IP (for example OpenMLA), with the three kinds of connection a block
// needs already wired, and a self-test on each so the connections can be checked on the board before the IP exists.
//   1. Registers: a 16 KiB AXI4-Lite window (BAR0 + 0x4000, rig 0xF8004000; `clk` = the register clock). Replace the body, keep the ports.
//   2. Interrupts: `irq[UIRQ-1:0]`, levels to the host (MSI/INTx through XDMA user interrupts 2..UIRQ+1; vector 1 is user_regs, 0 the CPU doorbell).
//      One message per assertion (irq_req.v): clear the cause and re-read until none is pending. `irq_pend` shows the requests in flight.
//   3. DDR4: UMEM independent AXI4 master ports (256-bit data, 32-bit address, 4-bit ids, `mclk` = the DDR4 user clock). Ports share the controller
//      with the rig and the PCIe DMA through one crossbar; each gets its share under contention, none has a reserved bandwidth.
// Window map (word offsets; unlisted words read 0 and ignore writes):
//   0x000 ID        RO  0x55495031 ("UIP1")
//   0x004 CAPS      RO  {16'h0001 layout, UIRQ[7:0], UMEM[7:0]}
//   0x008 IRQ_SET   RW  bit i drives irq[i] (the self-test source; an IP ORs its own cause in)
//   0x00C IRQ_PEND  RO  bit i: the request of irq[i] is waiting for the host (raised, not yet acknowledged). Needs a PCIe link: the core holds the
//                       interrupt logic in reset without one, so no request is raised then
//   0x010 IRQ_SEEN  RO  bit i: irq[i] as seen inside the PCIe clock domain (also without a link): shows the connection up to the XDMA interrupt logic
//   0x014 START     WO  bit i: start mem_probe i (same effect as its CTRL bit 0), all selected ports in the same clock; word write only
//   0x100 + 0x40*i  mem_probe i (self-test of DDR4 port i, registers in fpga/rtl/mem_probe.v), i < UMEM
module user_ip #(
    parameter UMEM = 2,
    parameter UIRQ = 6
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [13:0]         s_awaddr,
    input  wire                s_awvalid,
    output wire                s_awready,
    input  wire [31:0]         s_wdata,
    input  wire [3:0]          s_wstrb,
    input  wire                s_wvalid,
    output wire                s_wready,
    output wire [1:0]          s_bresp,
    output wire                s_bvalid,
    input  wire                s_bready,
    input  wire [13:0]         s_araddr,
    input  wire                s_arvalid,
    output wire                s_arready,
    output wire [31:0]         s_rdata,
    output wire [1:0]          s_rresp,
    output wire                s_rvalid,
    input  wire                s_rready,
    output wire [UIRQ-1:0]     irq,
    input  wire [UIRQ-1:0]     irq_pend,
    input  wire [UIRQ-1:0]     irq_seen,
    input  wire                mclk,
    input  wire                mrst_n,
    output wire [32*UMEM-1:0]  m_awaddr,
    output wire [8*UMEM-1:0]   m_awlen,
    output wire [3*UMEM-1:0]   m_awsize,
    output wire [2*UMEM-1:0]   m_awburst,
    output wire [4*UMEM-1:0]   m_awid,
    output wire [UMEM-1:0]     m_awvalid,
    input  wire [UMEM-1:0]     m_awready,
    output wire [256*UMEM-1:0] m_wdata,
    output wire [32*UMEM-1:0]  m_wstrb,
    output wire [UMEM-1:0]     m_wlast,
    output wire [UMEM-1:0]     m_wvalid,
    input  wire [UMEM-1:0]     m_wready,
    input  wire [4*UMEM-1:0]   m_bid,
    input  wire [2*UMEM-1:0]   m_bresp,
    input  wire [UMEM-1:0]     m_bvalid,
    output wire [UMEM-1:0]     m_bready,
    output wire [32*UMEM-1:0]  m_araddr,
    output wire [8*UMEM-1:0]   m_arlen,
    output wire [3*UMEM-1:0]   m_arsize,
    output wire [2*UMEM-1:0]   m_arburst,
    output wire [4*UMEM-1:0]   m_arid,
    output wire [UMEM-1:0]     m_arvalid,
    input  wire [UMEM-1:0]     m_arready,
    input  wire [4*UMEM-1:0]   m_rid,
    input  wire [256*UMEM-1:0] m_rdata,
    input  wire [2*UMEM-1:0]   m_rresp,
    input  wire [UMEM-1:0]     m_rlast,
    input  wire [UMEM-1:0]     m_rvalid,
    output wire [UMEM-1:0]     m_rready
);
    localparam [7:0] UMEM8 = UMEM, UIRQ8 = UIRQ;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [13:0] addr;   // bits 1:0 select the byte, not used
    /* verilator lint_on UNUSEDSIGNAL */
    wire        we, re;
    wire [31:0] wdata;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [3:0]  wstrb;   // word writes only
    /* verilator lint_on UNUSEDSIGNAL */
    reg  [31:0] rdata;

    axil_simple #(.AW(14)) u_bus (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .addr(addr), .we(we), .wdata(wdata), .wstrb(wstrb), .re(re), .rdata(rdata));

    // ------------------------------------------------------------ interrupts
    reg [UIRQ-1:0] irq_set;
    reg [UMEM-1:0] start;
    assign irq = irq_set;

    // ------------------------------------------------------------ self-test engines, one per DDR4 port
    wire [32*UMEM-1:0] pr_rdata;
    wire [7:0]  pidx_w = addr[13:6] - 8'd4;     // 0x100 + 0x40 * i
    wire        pwin_w = addr[13:8] != 6'd0 && addr[13:6] >= 8'd4 && pidx_w < UMEM && !addr[5];
    genvar g;
    generate
        for (g = 0; g < UMEM; g = g + 1) begin : g_probe
            mem_probe u_probe (
                .clk(clk), .rst_n(rst_n),
                .waddr(addr[4:2]), .we(we && pwin_w && pidx_w == g), .wdata(wdata), .go_ext(start[g]),
                .raddr(addr[4:2]), .rdata(pr_rdata[32*g +: 32]),
                .mclk(mclk), .mrst_n(mrst_n),
                .m_awaddr(m_awaddr[32*g +: 32]), .m_awlen(m_awlen[8*g +: 8]), .m_awsize(m_awsize[3*g +: 3]), .m_awburst(m_awburst[2*g +: 2]),
                .m_awid(m_awid[4*g +: 4]), .m_awvalid(m_awvalid[g]), .m_awready(m_awready[g]),
                .m_wdata(m_wdata[256*g +: 256]), .m_wstrb(m_wstrb[32*g +: 32]), .m_wlast(m_wlast[g]), .m_wvalid(m_wvalid[g]), .m_wready(m_wready[g]),
                .m_bid(m_bid[4*g +: 4]), .m_bresp(m_bresp[2*g +: 2]), .m_bvalid(m_bvalid[g]), .m_bready(m_bready[g]),
                .m_araddr(m_araddr[32*g +: 32]), .m_arlen(m_arlen[8*g +: 8]), .m_arsize(m_arsize[3*g +: 3]), .m_arburst(m_arburst[2*g +: 2]),
                .m_arid(m_arid[4*g +: 4]), .m_arvalid(m_arvalid[g]), .m_arready(m_arready[g]),
                .m_rid(m_rid[4*g +: 4]), .m_rdata(m_rdata[256*g +: 256]), .m_rresp(m_rresp[2*g +: 2]), .m_rlast(m_rlast[g]),
                .m_rvalid(m_rvalid[g]), .m_rready(m_rready[g]));
        end
    endgenerate

    always @(posedge clk) begin
        start <= {UMEM{1'b0}};
        if (we && addr[13:2] == 12'h005 && wstrb == 4'hF) start <= wdata[UMEM-1:0];
        if (!rst_n) irq_set <= {UIRQ{1'b0}};
        else if (we && addr[13:2] == 12'h002 && wstrb == 4'hF) irq_set <= wdata[UIRQ-1:0];
        if (re) begin
            rdata <= 32'd0;
            if (addr[13:8] == 6'd0) begin
                case (addr[7:2])
                6'h00: rdata <= 32'h55495031;
                6'h01: rdata <= {16'h0001, UIRQ8, UMEM8};
                6'h02: rdata <= {{(32-UIRQ){1'b0}}, irq_set};
                6'h03: rdata <= {{(32-UIRQ){1'b0}}, irq_pend};
                6'h04: rdata <= {{(32-UIRQ){1'b0}}, irq_seen};
                default: ;
                endcase
            end else if (pwin_w) rdata <= pr_rdata[32*pidx_w +: 32];
        end
    end
endmodule
