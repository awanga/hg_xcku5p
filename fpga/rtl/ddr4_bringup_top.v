// SPDX-License-Identifier: MIT
// DDR4 bring-up design: ddr4_0 (AXI, 256-bit) driven by axi_memtest; status on LEDs and UART1.
//  led[0] calibration complete   led[1] test running     led[2] >= 1 pass completed
//  led[3] error or timeout seen  led[4] ui_clk heartbeat led[7:5] unused (0)
// KEY_PL0 (active high when pressed) resets the memory controller and the test.
// UART1 TX is on a bank powered from VADJ: the board jumper must select 1.8 V (CP2105 VIO is 1.8 V).
module ddr4_bringup_top (
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
    output wire        uart_tx
);
    // Status UART and the ui_clk frequency counter run on CLK_50M so the console stays readable at any DDR4 speed.
    localparam CLKS_PER_BIT = 434; // 50 MHz / 115200

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

    // CA parity is disabled in the controller, which then has no PAR port; drive the DRAM PAR input low (DDR4 needs a valid level).
    assign c0_ddr4_par = 1'b0;

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

    wire clk50_i;
    IBUF u_clk50_ibuf (.I(clk50), .O(clk50_i));
    reg [3:0] rcnt = 4'd0;
    always @(posedge clk50_i)
        if (rcnt != 4'hF) rcnt <= rcnt + 1'b1;
    wire rst50_n = (rcnt == 4'hF);

    // ui_clk frequency: gate ui_clk edges for 0.25 s of CLK_50M (clear, count, settle, sample); the count is read
    // only while the gate is low, so it never changes during the transfer.
    reg [23:0] ph_cnt = 24'd0;
    reg [1:0]  ph = 2'd0;
    always @(posedge clk50_i) begin
        if (ph_cnt == 24'd12499999) begin
            ph_cnt <= 24'd0;
            ph <= ph + 1'b1;
        end else
            ph_cnt <= ph_cnt + 1'b1;
    end
    wire gate50 = (ph == 2'd1);
    wire clr50 = (ph == 2'd0);
    (* ASYNC_REG = "TRUE" *) reg [1:0] gate_s, clr_s;
    reg [31:0] ui_cnt = 32'd0;
    always @(posedge ui_clk) begin
        gate_s <= {gate_s[0], gate50};
        clr_s <= {clr_s[0], clr50};
        if (clr_s[1]) ui_cnt <= 32'd0;
        else if (gate_s[1]) ui_cnt <= ui_cnt + 1'b1;
    end
    reg [31:0] freq_hz = 32'd0;
    always @(posedge clk50_i)
        if (ph == 2'd3 && ph_cnt == 24'd0) freq_hz <= {ui_cnt[29:0], 2'b00};

    // Status inputs from ui_clk are registered twice on CLK_50M; they change rarely (one pass takes tens of ms), and
    // a torn sample would only show as one odd line.
    (* ASYNC_REG = "TRUE" *) reg [128:0] st_a, st_b;
    always @(posedge clk50_i) begin
        st_a <= {calib, pass_cnt, err_cnt, wr_cycles, rd_cycles};
        st_b <= st_a;
    end

    status_uart #(.CLKS_PER_BIT(CLKS_PER_BIT), .INTERVAL(25000000)) u_status (
        .clk(clk50_i), .rst_n(rst50_n), .calib(st_b[128]), .pass(st_b[127:96]), .err(st_b[95:64]),
        .wr(st_b[63:32]), .rd(st_b[31:0]), .freq(freq_hz), .tx(uart_tx));

    reg [26:0] hb;
    always @(posedge ui_clk)
        hb <= hb + 1'b1;

    assign led = {3'b000, hb[26], (err_cnt != 32'd0) || timeout, pass_cnt != 32'd0, busy, calib};
endmodule
