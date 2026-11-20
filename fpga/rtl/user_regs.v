// SPDX-License-Identifier: MIT
// Hook for future firmware functions on the CPU-less PCIe card (card_top): a 4 KiB AXI4-Lite window (BAR0 + 0x2000, rig 0xF8002000) with a small register
// file whose ports are the interface a new block attaches to. Nothing is connected today (`ctl` and `kick` go nowhere, `sts` is tied to 0).
//   0x000..0x03C CTL[0..15]  RW  drive `ctl` (flat, word i = ctl[32*i +: 32]); reset 0
//   0x040..0x07C STS[0..15]  RO  read `sts` (word i = sts[32*i +: 32]), sampled when read
//   0x080        KICK        WO  each written 1 bit pulses `kick` for one clock (a start/trigger for a function); reads 0
//   0x084        EVENT       RW1C bits set by `event_in` pulses; write 1 clears; `irq` is any event bit & IEN
//   0x088        IEN         RW  event interrupt enable mask
//   0x08C        VERSION     RO  0x00010000: the layout of this window
// KICK, EVENT and IEN accept only full-word writes (all four byte strobes). Everything else reads 0 and ignores writes. `irq` is a level; card_top does not use it yet (a future block would route it to a user interrupt of the host).
module user_regs (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [11:0]  s_awaddr,
    input  wire         s_awvalid,
    output wire         s_awready,
    input  wire [31:0]  s_wdata,
    input  wire [3:0]   s_wstrb,
    input  wire         s_wvalid,
    output wire         s_wready,
    output wire [1:0]   s_bresp,
    output wire         s_bvalid,
    input  wire         s_bready,
    input  wire [11:0]  s_araddr,
    input  wire         s_arvalid,
    output wire         s_arready,
    output wire [31:0]  s_rdata,
    output wire [1:0]   s_rresp,
    output wire         s_rvalid,
    input  wire         s_rready,
    output wire [511:0] ctl,
    input  wire [511:0] sts,
    output reg  [31:0]  kick,
    input  wire [31:0]  event_in,
    output wire         irq
);
    /* verilator lint_off UNUSEDSIGNAL */
    wire [11:0] addr;   // bits 1:0 select the byte, not used
    /* verilator lint_on UNUSEDSIGNAL */
    wire        we, re;
    wire [31:0] wdata;
    wire [3:0]  wstrb;
    reg  [31:0] rdata;

    axil_simple #(.AW(12)) u_bus (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .addr(addr), .we(we), .wdata(wdata), .wstrb(wstrb), .re(re), .rdata(rdata));

    reg [31:0] ctl_q [0:15];
    reg [31:0] events, ien;
    integer i;
    wire [9:0] w = addr[11:2];

    assign irq = |(events & ien);
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : g_ctl
            assign ctl[32*g +: 32] = ctl_q[g];
        end
    endgenerate

    always @(posedge clk) begin
        kick <= 32'd0;
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) ctl_q[i] <= 32'd0;
            events <= 32'd0;
            ien <= 32'd0;
        end else begin
            events <= events | event_in;
            if (we) begin
                if (w < 10'd16) begin
                    for (i = 0; i < 4; i = i + 1)
                        if (wstrb[i]) ctl_q[w[3:0]][8*i +: 8] <= wdata[8*i +: 8];
                end
                if (w == 10'h20 && wstrb == 4'hF) kick <= wdata;
                if (w == 10'h21 && wstrb == 4'hF) events <= (events | event_in) & ~wdata;
                if (w == 10'h22 && wstrb == 4'hF) ien <= wdata;
            end
        end
        if (re) begin
            if (addr[11:2] < 10'd16) rdata <= ctl_q[addr[5:2]];
            else if (addr[11:6] == 6'd1) rdata <= sts[32*addr[5:2] +: 32];
            else case (w)
            10'h21: rdata <= events;
            10'h22: rdata <= ien;
            10'h23: rdata <= 32'h00010000;
            default: rdata <= 32'd0;
            endcase
        end
    end
endmodule
