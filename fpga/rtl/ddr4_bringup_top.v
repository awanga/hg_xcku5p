// SPDX-License-Identifier: MIT
// DDR4 bring-up design: ddr4_0 (AXI, 256-bit) driven by axi_memtest; status on LEDs and UART1.
//  led[0] calibration complete   led[1] test running     led[2] >= 1 pass completed
//  led[3] error or timeout seen  led[4] ui_clk heartbeat led[7:5] unused (0)
// KEY_PL0 (active high when pressed) resets the memory controller and the test.
// UART1 TX is on a bank powered from VADJ: the board jumper must select 1.8 V (CP2105 VIO is 1.8 V).
module ddr4_bringup_top #(
    parameter UI_CLK_HZ = 200000000  // 4 / tCK: 200 MHz at 1250 ps, 250 MHz at 1000 ps, 333.33 MHz at 750 ps
) (
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
    output wire        c0_ddr4_reset_n,
    inout  wire [3:0]  c0_ddr4_dm_dbi_n,
    inout  wire [31:0] c0_ddr4_dq,
    inout  wire [3:0]  c0_ddr4_dqs_t,
    inout  wire [3:0]  c0_ddr4_dqs_c,
    input  wire        key_rst,
    output wire [7:0]  led,
    output wire        uart_tx
);
    localparam BAUD = 115200;
    localparam CLKS_PER_BIT = (UI_CLK_HZ + BAUD / 2) / BAUD;

    wire         ui_clk;
    wire         ui_rst;
    wire         calib;
    wire         aresetn = ~ui_rst;

    wire [29:0]  awaddr, araddr, first_err_addr;
    wire         awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire         arvalid, arready, rvalid, rready, rlast;
    wire [255:0] wdata, rdata;
    wire [1:0]   bresp, rresp;
    wire [31:0]  pass_cnt, err_cnt, wr_cycles, rd_cycles;
    wire         timeout, busy;

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
        .c0_ddr4_aresetn(aresetn),
        .c0_ddr4_s_axi_awid(4'd0),
        .c0_ddr4_s_axi_awaddr(awaddr),
        .c0_ddr4_s_axi_awlen(8'd15),
        .c0_ddr4_s_axi_awsize(3'd5),
        .c0_ddr4_s_axi_awburst(2'b01),
        .c0_ddr4_s_axi_awlock(1'b0),
        .c0_ddr4_s_axi_awcache(4'd0),
        .c0_ddr4_s_axi_awprot(3'd0),
        .c0_ddr4_s_axi_awqos(4'd0),
        .c0_ddr4_s_axi_awvalid(awvalid),
        .c0_ddr4_s_axi_awready(awready),
        .c0_ddr4_s_axi_wdata(wdata),
        .c0_ddr4_s_axi_wstrb({32{1'b1}}),
        .c0_ddr4_s_axi_wlast(wlast),
        .c0_ddr4_s_axi_wvalid(wvalid),
        .c0_ddr4_s_axi_wready(wready),
        .c0_ddr4_s_axi_bready(bready),
        .c0_ddr4_s_axi_bid(),
        .c0_ddr4_s_axi_bresp(bresp),
        .c0_ddr4_s_axi_bvalid(bvalid),
        .c0_ddr4_s_axi_arid(4'd0),
        .c0_ddr4_s_axi_araddr(araddr),
        .c0_ddr4_s_axi_arlen(8'd15),
        .c0_ddr4_s_axi_arsize(3'd5),
        .c0_ddr4_s_axi_arburst(2'b01),
        .c0_ddr4_s_axi_arlock(1'b0),
        .c0_ddr4_s_axi_arcache(4'd0),
        .c0_ddr4_s_axi_arprot(3'd0),
        .c0_ddr4_s_axi_arqos(4'd0),
        .c0_ddr4_s_axi_arvalid(arvalid),
        .c0_ddr4_s_axi_arready(arready),
        .c0_ddr4_s_axi_rready(rready),
        .c0_ddr4_s_axi_rlast(rlast),
        .c0_ddr4_s_axi_rvalid(rvalid),
        .c0_ddr4_s_axi_rresp(rresp),
        .c0_ddr4_s_axi_rid(),
        .c0_ddr4_s_axi_rdata(rdata),
        .sys_rst(key_rst));

    axi_memtest #(.NBURSTS(131072), .TIMEOUT_BITS(26)) u_test (
        .clk(ui_clk), .rst_n(aresetn), .enable(calib),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .pass_cnt(pass_cnt), .err_cnt(err_cnt), .wr_cycles(wr_cycles), .rd_cycles(rd_cycles),
        .first_err_addr(first_err_addr), .timeout(timeout), .busy(busy));

    status_uart #(.CLKS_PER_BIT(CLKS_PER_BIT), .INTERVAL(UI_CLK_HZ / 2)) u_status (
        .clk(ui_clk), .rst_n(aresetn), .calib(calib), .pass(pass_cnt), .err(err_cnt),
        .wr(wr_cycles), .rd(rd_cycles), .tx(uart_tx));

    reg [26:0] hb;
    always @(posedge ui_clk)
        hb <= hb + 1'b1;

    assign led = {3'b000, hb[26], (err_cnt != 32'd0) || timeout, pass_cnt != 32'd0, busy, calib};
endmodule
