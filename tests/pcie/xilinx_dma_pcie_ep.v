// SPDX-License-Identifier: MIT
// Simulation top that takes the place of the vendor example's `xilinx_dma_pcie_ep` in the root-port testbench (board.v): our pcie_ep with a
// behavioural 64 KiB memory behind its DMA master (what the SoC's DDR is) and a CPU agent that drives the CPU-side register window. The port
// list is the one board.v instantiates (PIPE-mode simulation: the TX/RX pairs are not used). Tests reach the agent hierarchically:
//   board.EP.cpu_write(addr, data), board.EP.cpu_read(addr) -> board.EP.cpu_rdata, board.EP.mem[], board.EP.aw_count / ar_count, board.EP.irq
`timescale 1ps / 1ps
module xilinx_dma_pcie_ep #(
    parameter EXT_PIPE_SIM = "TRUE"
) (
    output [3:0]  pci_exp_txp,
    output [3:0]  pci_exp_txn,
    input  [3:0]  pci_exp_rxp,
    input  [3:0]  pci_exp_rxn,
    input  [25:0] common_commands_in,
    output [25:0] common_commands_out,
    input  [83:0] pipe_rx_0_sigs,
    input  [83:0] pipe_rx_1_sigs,
    input  [83:0] pipe_rx_2_sigs,
    input  [83:0] pipe_rx_3_sigs,
    input  [83:0] pipe_rx_4_sigs,
    input  [83:0] pipe_rx_5_sigs,
    input  [83:0] pipe_rx_6_sigs,
    input  [83:0] pipe_rx_7_sigs,
    input  [83:0] pipe_rx_8_sigs,
    input  [83:0] pipe_rx_9_sigs,
    input  [83:0] pipe_rx_10_sigs,
    input  [83:0] pipe_rx_11_sigs,
    input  [83:0] pipe_rx_12_sigs,
    input  [83:0] pipe_rx_13_sigs,
    input  [83:0] pipe_rx_14_sigs,
    input  [83:0] pipe_rx_15_sigs,
    output [83:0] pipe_tx_0_sigs,
    output [83:0] pipe_tx_1_sigs,
    output [83:0] pipe_tx_2_sigs,
    output [83:0] pipe_tx_3_sigs,
    output [83:0] pipe_tx_4_sigs,
    output [83:0] pipe_tx_5_sigs,
    output [83:0] pipe_tx_6_sigs,
    output [83:0] pipe_tx_7_sigs,
    output [83:0] pipe_tx_8_sigs,
    output [83:0] pipe_tx_9_sigs,
    output [83:0] pipe_tx_10_sigs,
    output [83:0] pipe_tx_11_sigs,
    output [83:0] pipe_tx_12_sigs,
    output [83:0] pipe_tx_13_sigs,
    output [83:0] pipe_tx_14_sigs,
    output [83:0] pipe_tx_15_sigs,
    input  sys_clk_p,
    input  sys_clk_n,
    input  sys_rst_n
);
    // names the vendor interrupt tests (not run here) refer to; the endpoint's own request is board.EP.u_ep.usr_irq_req
    localparam C_NUM_USR_IRQ = 4;
    reg [C_NUM_USR_IRQ-1:0] usr_irq_req = 4'd0;
    wire [C_NUM_USR_IRQ-1:0] usr_irq_ack = u_ep.usr_irq_ack;
    // the XDMA master's write data as the vendor C2H data checker expects to find it here
    wire         user_clk = u_ep.axi_aclk;
    wire [127:0] m_axi_wdata = u_ep.x_wdata;
    wire [15:0]  m_axi_wstrb = u_ep.x_wstrb;
    wire         m_axi_wvalid = u_ep.x_wvalid;
    wire         m_axi_wready = u_ep.x_wready;
    reg clk = 1'b0, per_clk = 1'b0, rst_n = 1'b0, per_rst_n = 1'b0;
    always #1500 clk = ~clk;        // 333.3 MHz CPU clock
    always #5000 per_clk = ~per_clk; // 100 MHz peripheral clock
    initial begin
        #200000 rst_n = 1'b1; per_rst_n = 1'b1;
    end

    wire [3:0]  m_awid, m_bid, m_arid, m_rid;
    wire [31:0] m_awaddr, m_araddr;
    wire [7:0]  m_awlen, m_arlen, m_wstrb;
    wire [2:0]  m_awsize, m_arsize;
    wire [1:0]  m_awburst, m_arburst;
    reg  [1:0]  m_bresp = 2'b00, m_rresp = 2'b00;
    wire [63:0] m_wdata;
    reg  [63:0] m_rdata = 64'd0;
    wire        m_awvalid, m_wlast, m_wvalid, m_bready, m_arvalid, m_rready;
    reg         m_awready = 1'b0, m_bvalid = 1'b0, m_arready = 1'b0, m_rvalid = 1'b0, m_rlast = 1'b0;
    wire        m_wready;

    reg  [6:0]  c_awaddr = 7'd0, c_araddr = 7'd0;
    reg  [31:0] c_wdata = 32'd0;
    reg         c_awvalid = 1'b0, c_wvalid = 1'b0, c_bready = 1'b1, c_arvalid = 1'b0, c_rready = 1'b1;
    wire        c_awready, c_wready, c_bvalid, c_arready, c_rvalid;
    wire [1:0]  c_bresp, c_rresp;
    wire [31:0] c_rdata;
    wire        irq;

`ifdef NOCPU
    // CPU-less build: the host's BAR0 is an AXI4-Lite master port (per_clk) onto the peripheral crossbar; here a 64 KiB word memory stands in for it
    // (word i holds C0DE0000 + i, so a read shows which address reached the port); the last write address, strobes and counts are recorded.
    wire [15:0] hl_awaddr, hl_araddr;
    wire [31:0] hl_wdata;
    wire [3:0]  hl_wstrb;
    wire        hl_awvalid, hl_wvalid, hl_bready, hl_arvalid, hl_rready;
    reg         hl_awready = 1'b0, hl_wready = 1'b0, hl_bvalid = 1'b0, hl_arready = 1'b0, hl_rvalid = 1'b0;
    wire [1:0]  hl_bresp = 2'b00, hl_rresp = 2'b00;
    reg  [31:0] hl_rdata = 32'd0;
    reg  [31:0] hmem [0:16383];
    integer     hl_wr_n = 0, hl_rd_n = 0, hi;
    reg  [15:0] hl_last_wa = 16'd0, hl_last_ra = 16'd0;
    reg  [3:0]  hl_last_ws = 4'd0;
    reg         hl_aws = 1'b0, hl_ws = 1'b0;
    reg  [15:0] hl_a = 16'd0;
    reg  [31:0] hl_d = 32'd0;
    reg  [3:0]  hl_s = 4'd0;
    initial for (hi = 0; hi < 16384; hi = hi + 1) hmem[hi] = 32'hC0DE0000 + hi;
    always @(posedge per_clk) begin
        hl_awready <= hl_awvalid && !hl_awready && !hl_aws;
        hl_wready <= hl_wvalid && !hl_wready && !hl_ws;
        if (hl_awvalid && hl_awready) begin hl_a <= hl_awaddr; hl_aws <= 1'b1; hl_last_wa <= hl_awaddr; end
        if (hl_wvalid && hl_wready) begin hl_d <= hl_wdata; hl_s <= hl_wstrb; hl_ws <= 1'b1; hl_last_ws <= hl_wstrb; end
        if (hl_aws && hl_ws && !hl_bvalid) begin
            if (hl_s[0]) hmem[hl_a[15:2]][7:0] <= hl_d[7:0];
            if (hl_s[1]) hmem[hl_a[15:2]][15:8] <= hl_d[15:8];
            if (hl_s[2]) hmem[hl_a[15:2]][23:16] <= hl_d[23:16];
            if (hl_s[3]) hmem[hl_a[15:2]][31:24] <= hl_d[31:24];
            hl_bvalid <= 1'b1; hl_aws <= 1'b0; hl_ws <= 1'b0; hl_wr_n <= hl_wr_n + 1;
        end
        if (hl_bvalid && hl_bready) hl_bvalid <= 1'b0;
        hl_arready <= hl_arvalid && !hl_arready && !hl_rvalid;
        if (hl_arvalid && hl_arready) begin hl_rdata <= hmem[hl_araddr[15:2]]; hl_rvalid <= 1'b1; hl_last_ra <= hl_araddr; hl_rd_n <= hl_rd_n + 1; end
        if (hl_rvalid && hl_rready) hl_rvalid <= 1'b0;
    end
`endif

    pcie_ep u_ep (
        .sys_clk_p(sys_clk_p), .sys_clk_n(sys_clk_n), .sys_rst_n(sys_rst_n),
        .pci_exp_txp(pci_exp_txp), .pci_exp_txn(pci_exp_txn), .pci_exp_rxp(pci_exp_rxp), .pci_exp_rxn(pci_exp_rxn),
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
        .clk(clk), .rst_n(rst_n), .per_clk(per_clk), .per_rst_n(per_rst_n),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awvalid(m_awvalid),
        .m_awready(m_awready), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast), .m_rvalid(m_rvalid),
        .m_rready(m_rready),
        .c_awaddr(c_awaddr), .c_awvalid(c_awvalid), .c_awready(c_awready), .c_wdata(c_wdata), .c_wstrb(4'hF), .c_wvalid(c_wvalid),
        .c_wready(c_wready), .c_bresp(c_bresp), .c_bvalid(c_bvalid), .c_bready(c_bready),
        .c_araddr(c_araddr), .c_arvalid(c_arvalid), .c_arready(c_arready), .c_rdata(c_rdata), .c_rresp(c_rresp), .c_rvalid(c_rvalid),
`ifdef NOCPU
        .hl_awaddr(hl_awaddr), .hl_awvalid(hl_awvalid), .hl_awready(hl_awready), .hl_wdata(hl_wdata), .hl_wstrb(hl_wstrb), .hl_wvalid(hl_wvalid),
        .hl_wready(hl_wready), .hl_bresp(hl_bresp), .hl_bvalid(hl_bvalid), .hl_bready(hl_bready),
        .hl_araddr(hl_araddr), .hl_arvalid(hl_arvalid), .hl_arready(hl_arready), .hl_rdata(hl_rdata), .hl_rresp(hl_rresp), .hl_rvalid(hl_rvalid),
        .hl_rready(hl_rready),
`endif
        .c_rready(c_rready), .irq(irq), .uirq(7'd0), .uirq_pend(), .uirq_seen());

    // ---------------------------------------------------------------- the SoC memory: 64 KiB, one burst at a time, deterministic stalls
    reg [7:0] mem [0:65535];
    integer aw_count = 0, ar_count = 0, w_beats = 0, r_beats = 0;
    integer i0;
    initial for (i0 = 0; i0 < 65536; i0 = i0 + 1) mem[i0] = 8'hEE;
    reg [31:0] wa, ra;
    reg [7:0]  wl, rl;
    reg        w_act = 1'b0, b_pend = 1'b0, r_act = 1'b0;
    integer    wc, rc, k, j;
    reg [3:0]  wcycle = 4'd0;
    always @(posedge clk) wcycle <= wcycle + 4'd1;
    assign m_wready = w_act && wcycle[1];
    assign m_bid = 4'd0;
    assign m_rid = 4'd0;
    always @(posedge clk) begin
        m_awready <= 1'b0;
        if (m_bvalid && m_bready) m_bvalid <= 1'b0;
        if (!w_act && !b_pend && !m_bvalid && m_awvalid && !m_awready) begin
            m_awready <= 1'b1; wa <= m_awaddr; wl <= m_awlen; w_act <= 1'b1; wc <= 0; aw_count <= aw_count + 1;
        end else if (w_act && m_wvalid && m_wready) begin
            for (k = 0; k < 8; k = k + 1) if (m_wstrb[k]) mem[(wa + 8 * wc + k) & 65535] <= m_wdata[8 * k +: 8];
            wc <= wc + 1; w_beats <= w_beats + 1;
            if (m_wlast) begin w_act <= 1'b0; b_pend <= 1'b1; end
        end else if (b_pend) begin
            m_bvalid <= 1'b1; m_bresp <= 2'b00; b_pend <= 1'b0;
        end
    end
    always @(posedge clk) begin
        m_arready <= 1'b0;
        if (m_rvalid && m_rready) begin m_rvalid <= 1'b0; if (m_rlast) r_act <= 1'b0; end
        if (!r_act && m_arvalid && !m_arready) begin
            m_arready <= 1'b1; ra <= m_araddr; rl <= m_arlen; r_act <= 1'b1; rc <= 0; ar_count <= ar_count + 1;
        end else if (r_act && !m_arready && (!m_rvalid || m_rready) && !(m_rvalid && m_rlast) && rc <= rl && wcycle[0]) begin
            for (j = 0; j < 8; j = j + 1) m_rdata[8 * j +: 8] <= mem[(ra + 8 * rc + j) & 65535];
            m_rresp <= 2'b00; m_rlast <= (rc == rl); m_rvalid <= 1'b1; rc <= rc + 1; r_beats <= r_beats + 1;
        end
    end

    // ---------------------------------------------------------------- CPU agent (AXI4-Lite master in per_clk; tasks are called from the test)
    reg [31:0] cpu_rdata;
    task cpu_write(input [6:0] a, input [31:0] d);
        begin
            @(negedge per_clk);
            c_awaddr = a; c_wdata = d; c_awvalid = 1'b1; c_wvalid = 1'b1;
            #1000; while (!(c_awready && c_wready)) begin @(negedge per_clk); #1000; end
            @(posedge per_clk);
            @(negedge per_clk); c_awvalid = 1'b0; c_wvalid = 1'b0;
            #1000; while (!c_bvalid) begin @(negedge per_clk); #1000; end
            @(posedge per_clk);
        end
    endtask
    task cpu_read(input [6:0] a);
        begin
            @(negedge per_clk);
            c_araddr = a; c_arvalid = 1'b1;
            #1000; while (!c_arready) begin @(negedge per_clk); #1000; end
            @(posedge per_clk);
            @(negedge per_clk); c_arvalid = 1'b0;
            #1000; while (!c_rvalid) begin @(negedge per_clk); #1000; end
            cpu_rdata = c_rdata;
            @(posedge per_clk);
        end
    endtask

    // ---------------------------------------------------------------- root-port side helpers (BFM tasks of the vendor test bench)
    reg [31:0] host_rdata;
    integer lite_bar = -1;
    task find_lite_bar;
        integer b;
        begin
            lite_bar = -1;
            for (b = 5; b >= 0; b = b - 1)
                if (board.RP.tx_usrapp.BAR_INIT_P_BAR_ENABLED[b] > 2'b01 && b != board.RP.tx_usrapp.xdma_bar) lite_bar = b;
        end
    endtask
    task host_rd(input [31:0] off);
        begin
            board.RP.tx_usrapp.P_READ_DATA = 32'hffff_ffff;
            fork
                board.RP.tx_usrapp.TSK_TX_BAR_READ(lite_bar[2:0], off, board.RP.tx_usrapp.DEFAULT_TAG, board.RP.tx_usrapp.DEFAULT_TC);
                board.RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
            join
            host_rdata = board.RP.tx_usrapp.P_READ_DATA;
            board.RP.tx_usrapp.TSK_TX_CLK_EAT(10);
            board.RP.tx_usrapp.DEFAULT_TAG = board.RP.tx_usrapp.DEFAULT_TAG + 1;
        end
    endtask
    task host_wr(input [31:0] off, input [31:0] data);
        begin
            board.RP.tx_usrapp.TSK_TX_BAR_WRITE(lite_bar[2:0], off, board.RP.tx_usrapp.DEFAULT_TAG, board.RP.tx_usrapp.DEFAULT_TC, data);
            board.RP.tx_usrapp.TSK_TX_CLK_EAT(30);
            board.RP.tx_usrapp.DEFAULT_TAG = board.RP.tx_usrapp.DEFAULT_TAG + 1;
            #1000000;   // a posted write needs the AXI-Lite clock converter and the peripheral clock before it is visible to the CPU
        end
    endtask
endmodule
