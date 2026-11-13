// SPDX-License-Identifier: MIT
// HDMI/DVI TMDS output: register file + line fetcher (AXI clock domain `clk`), timing, TMDS encoders and serializers (pixel clock `pclk` and 5x `clk5`).
// Fixed mode 1024x768@60 (parameters), RGB565 frame buffer, 2048 bytes per line. The board's DDC pins are not wired, so there is no EDID.
//
// Registers (byte addresses; AXI4-Lite, 32 bit):
//   0x00 CTRL    bit0 = ENABLE (scan-out and timing run), bit1 = OE (HDMI connector 5 V switch / output enable)
//   0x04 FB_BASE frame buffer physical address (2048-byte aligned, low 11 bits read as written but ignored by the fetcher's burst addressing)
//   0x08 STATUS  bit0 = HPD (hot-plug detect, sampled), bit1 = RUNNING (timing active, synchronised), bit2 = LATE (sticky), bit3 = RERR (sticky); write 1 to bit2/3 or bit4 to clear counters
//   0x0C FRAMES  frames since ENABLE (counts vsync starts)
//   0x10 LATE    lines that were not fetched in time
//   0x14 LINES   lines fetched
//   0x18 MODE    {width[15:0], height[15:0]} = 1024 x 768 (read only)
module hdmi_out #(
    parameter H_ACTIVE = 1024,
    parameter H_FRONT = 24,
    parameter H_SYNC = 136,
    parameter H_BACK = 160,
    parameter V_ACTIVE = 768,
    parameter V_FRONT = 3,
    parameter V_SYNC = 6,
    parameter V_BACK = 29,
    parameter BURST = 16
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pclk,
    input  wire        clk5,
    // register slave
    input  wire [4:0]  s_awaddr,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,
    input  wire [4:0]  s_araddr,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rvalid,
    input  wire        s_rready,
    // AXI4 read master (frame buffer)
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire        m_arvalid,
    input  wire        m_arready,
    input  wire [63:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rvalid,
    output wire        m_rready,
    // board pins
    input  wire        hpd,
    output wire        oe,
    output wire [3:0]  ser  // {clock, red, green, blue}, to OBUFDS
);
    localparam LINE_BEATS = H_ACTIVE * 2 / 8;

    // ---- registers
    wire [4:0]  reg_addr;
    wire        reg_we, reg_re;
    wire [31:0] reg_wdata;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [3:0]  reg_wstrb;
    /* verilator lint_on UNUSEDSIGNAL */
    reg  [31:0] reg_rdata;
    reg         enable = 1'b0, oe_r = 1'b0;
    reg  [31:0] fb_base = 32'd0;
    reg         clr = 1'b0;
    reg         late_s = 1'b0, rerr_s = 1'b0;

    axil_simple #(.AW(5)) u_regs (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .addr(reg_addr), .we(reg_we), .wdata(reg_wdata), .wstrb(reg_wstrb), .re(reg_re), .rdata(reg_rdata));
    wire unused_re = reg_re;

    wire [31:0] late, lines, frames;
    wire        rerr, busy_unused;
    (* ASYNC_REG = "TRUE" *) reg hpd_s1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg hpd_s2 = 1'b0;
    wire        running_c;
    (* ASYNC_REG = "TRUE" *) reg run_s1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg run_s2 = 1'b0;
    always @(posedge clk) begin
        hpd_s1 <= hpd;
        hpd_s2 <= hpd_s1;
        run_s1 <= running_c;
        run_s2 <= run_s1;
    end

    always @(posedge clk) begin
        clr <= 1'b0;
        if (!rst_n) begin
            enable <= 1'b0;
            oe_r <= 1'b0;
            fb_base <= 32'd0;
        end else if (reg_we) begin
            case (reg_addr[4:2])
                3'd0: begin
                    enable <= reg_wdata[0];
                    oe_r <= reg_wdata[1];
                end
                3'd1: fb_base <= reg_wdata;
                3'd2: if (reg_wdata[4]) clr <= 1'b1;
                default: ;
            endcase
        end
        case (reg_addr[4:2])
            3'd0: reg_rdata <= {30'd0, oe_r, enable};
            3'd1: reg_rdata <= fb_base;
            3'd2: reg_rdata <= {28'd0, rerr, (late != 32'd0), run_s2, hpd_s2};
            3'd3: reg_rdata <= frames;
            3'd4: reg_rdata <= late;
            3'd5: reg_rdata <= lines;
            default: reg_rdata <= H_ACTIVE * 65536 + V_ACTIVE;
        endcase
    end
    assign oe = oe_r;

    // ---- line fetch (clk domain)
    wire        t_req;
    wire [9:0]  t_line;
    wire        ram_we;
    wire [8:0]  ram_waddr;
    wire [63:0] ram_wdata;
    hdmi_fetch #(.LINE_BEATS(LINE_BEATS), .BURST(BURST)) u_fetch (
        .clk(clk), .rst_n(rst_n), .en(enable), .fb_base(fb_base), .req(t_req), .line_no(t_line), .clr(clr),
        .araddr(m_araddr), .arlen(m_arlen), .arvalid(m_arvalid), .arready(m_arready), .rdata(m_rdata), .rresp(m_rresp),
        .rvalid(m_rvalid), .rready(m_rready), .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata),
        .late(late), .lines(lines), .rerr(rerr), .busy(busy_unused));

    // ---- pixel domain
    (* ASYNC_REG = "TRUE" *) reg en_p1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg en_p2 = 1'b0;
    always @(posedge pclk) begin
        en_p1 <= enable;
        en_p2 <= en_p1;
    end
    assign running_c = en_p2;

    wire [11:0] x, y;
    wire        de_t, hs_t, vs_t, frame_start;
    hdmi_timing #(.H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
                  .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK)) u_timing (
        .pclk(pclk), .rst(~en_p2), .x(x), .y(y), .de(de_t), .hsync(hs_t), .vsync(vs_t),
        .line_req(t_req), .line_no(t_line), .frame_start(frame_start));

    // frame counter: count frame_start in the pixel domain, read it in clk through a toggle
    reg        fs_tg = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg [2:0] fs_s = 3'd0;
    reg [31:0] frames_r = 32'd0;
    always @(posedge pclk) if (frame_start) fs_tg <= ~fs_tg;
    always @(posedge clk) begin
        fs_s <= {fs_s[1:0], fs_tg};
        if (!enable) frames_r <= 32'd0;
        else if (fs_s[1] ^ fs_s[2]) frames_r <= frames_r + 32'd1;
    end
    assign frames = frames_r;

    // pipeline: RAM address (cycle 0) -> RAM data (cycle 1) -> lane select (cycle 2) -> encoder input registered (cycle 3)
    wire [63:0] lb_rdata;
    hdmi_linebuf u_lb (.wclk(clk), .we(ram_we), .waddr(ram_waddr), .wdata(ram_wdata), .rclk(pclk), .raddr({y[0], x[9:2]}), .rdata(lb_rdata));
    reg [1:0] lane1;
    reg [1:0] de_d, hs_d, vs_d;
    reg [15:0] pix;
    reg [7:0] r8, g8, b8;
    reg       de3, hs3, vs3;
    always @(posedge pclk) begin
        lane1 <= x[1:0];
        de_d <= {de_d[0], de_t};
        hs_d <= {hs_d[0], hs_t};
        vs_d <= {vs_d[0], vs_t};
        case (lane1)
            2'd0: pix <= lb_rdata[15:0];
            2'd1: pix <= lb_rdata[31:16];
            2'd2: pix <= lb_rdata[47:32];
            default: pix <= lb_rdata[63:48];
        endcase
        r8 <= {pix[15:11], pix[15:13]};
        g8 <= {pix[10:5], pix[10:9]};
        b8 <= {pix[4:0], pix[4:2]};
        de3 <= de_d[1];
        hs3 <= hs_d[1];
        vs3 <= vs_d[1];
    end

    wire [9:0] q_b, q_g, q_r;
    // while disabled the syncs idle at their inactive level (high: both polarities are negative in this mode)
    tmds_encoder u_enc_b (.clk(pclk), .d(b8), .c(en_p2 ? {vs3, hs3} : 2'b11), .de(de3), .q(q_b));
    tmds_encoder u_enc_g (.clk(pclk), .d(g8), .c(2'b00), .de(de3), .q(q_g));
    tmds_encoder u_enc_r (.clk(pclk), .d(r8), .c(2'b00), .de(de3), .q(q_r));

    // words and toggle registered together in the pixel domain
    reg [9:0] w_b, w_g, w_r;
    reg       tg = 1'b0;
    always @(posedge pclk) begin
        w_b <= q_b;
        w_g <= q_g;
        w_r <= q_r;
        tg <= ~tg;
    end
    tmds_ser u_ser_b (.clk5(clk5), .tg(tg), .word(w_b), .q(ser[0]));
    tmds_ser u_ser_g (.clk5(clk5), .tg(tg), .word(w_g), .q(ser[1]));
    tmds_ser u_ser_r (.clk5(clk5), .tg(tg), .word(w_r), .q(ser[2]));
    tmds_ser u_ser_c (.clk5(clk5), .tg(tg), .word(10'b1111100000), .q(ser[3]));
endmodule
