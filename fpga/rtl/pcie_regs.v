// SPDX-License-Identifier: MIT
// Host/CPU shared register block of the PCIe endpoint. Two AXI4-Lite slaves in the SoC clock: `h_*` is the host's BAR0 window (arriving
// through a clock converter, so it only moves while the PCIe core is clocked), `c_*` is the CPU's peripheral window. Both see the same
// 128-byte map (word offsets); a host window larger than 128 bytes aliases, and every response is OKAY.
//   0x00 ID        RO   0x50434901 ("PCI", layout 1)
//   0x04 STATUS    RO   bit0 link up, bit1 PCIe core clock running, bit2 PERST# deasserted, bit3 host doorbell pending, bit4 CPU doorbell pending,
//                       bit5 link has been up since reset (sticky; the CPU clears it by writing 1 to bit5)
//   0x08 HOST_DB   host write 1 sets bits, CPU write 1 clears bits (a set and a clear of the same bit in one cycle: the set wins), reads give the
//                       pending bits (host -> CPU doorbell)
//   0x0C CPU_DB    CPU write 1 sets bits, host write 1 clears bits (CPU -> host doorbell; any pending bit raises usr_irq to the host)
//   0x10 IEN       CPU only: bit0 enables `irq` = any HOST_DB bit pending (a level held until the CPU clears the bits)
//   0x14 HOST_WR   RO   host register writes accepted (wraps)
//   0x18 HOST_RD   RO   host register reads accepted (wraps)
//   0x70 WIN_BASE CPU only: base address of the window the host's DMA may reach (read back by the CPU; the host reads 0)
//   0x74 WIN_SIZE CPU only: window size in bytes, 0 = closed (the reset state); consumed by axi_win through cdc_cfg
//   0x20..0x5C MAILBOX[0..15] read/write from both sides; if both write the same cycle, the CPU wins
// The status inputs come from other clock domains and are synchronised here (two flops each).
module pcie_regs (
    input  wire        clk,
    input  wire        rst_n,
    // host window
    input  wire [6:0]  h_awaddr,
    input  wire        h_awvalid,
    output wire        h_awready,
    input  wire [31:0] h_wdata,
    input  wire [3:0]  h_wstrb,
    input  wire        h_wvalid,
    output wire        h_wready,
    output wire [1:0]  h_bresp,
    output wire        h_bvalid,
    input  wire        h_bready,
    input  wire [6:0]  h_araddr,
    input  wire        h_arvalid,
    output wire        h_arready,
    output wire [31:0] h_rdata,
    output wire [1:0]  h_rresp,
    output wire        h_rvalid,
    input  wire        h_rready,
    // CPU window
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
    // asynchronous status inputs
    input  wire        link_up_a,
    input  wire        aclk_toggle_a,   // toggles every cycle of the PCIe user clock
    input  wire        perst_n_a,
    output wire [31:0] win_base,
    output wire [31:0] win_size,
    output wire        irq,
    output wire        cpu_db_any
);
    localparam [31:0] ID = 32'h50434901;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [6:0]  h_addr, c_addr;
    wire        h_we, h_re, c_we, c_re;
    wire [3:0]  h_wstrb_q, c_wstrb_q;   // registers are written whole
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] h_wd, c_wd;
    reg  [31:0] h_rd, c_rd;

    axil_simple #(.AW(7)) u_host (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(h_awaddr), .s_awvalid(h_awvalid), .s_awready(h_awready),
        .s_wdata(h_wdata), .s_wstrb(h_wstrb), .s_wvalid(h_wvalid), .s_wready(h_wready),
        .s_bresp(h_bresp), .s_bvalid(h_bvalid), .s_bready(h_bready),
        .s_araddr(h_araddr), .s_arvalid(h_arvalid), .s_arready(h_arready),
        .s_rdata(h_rdata), .s_rresp(h_rresp), .s_rvalid(h_rvalid), .s_rready(h_rready),
        .addr(h_addr), .we(h_we), .wdata(h_wd), .wstrb(h_wstrb_q), .re(h_re), .rdata(h_rd));
    axil_simple #(.AW(7)) u_cpu (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(c_awaddr), .s_awvalid(c_awvalid), .s_awready(c_awready),
        .s_wdata(c_wdata), .s_wstrb(c_wstrb), .s_wvalid(c_wvalid), .s_wready(c_wready),
        .s_bresp(c_bresp), .s_bvalid(c_bvalid), .s_bready(c_bready),
        .s_araddr(c_araddr), .s_arvalid(c_arvalid), .s_arready(c_arready),
        .s_rdata(c_rdata), .s_rresp(c_rresp), .s_rvalid(c_rvalid), .s_rready(c_rready),
        .addr(c_addr), .we(c_we), .wdata(c_wd), .wstrb(c_wstrb_q), .re(c_re), .rdata(c_rd));

    // synchronisers
    (* ASYNC_REG = "TRUE" *) reg [1:0] link_s, tog_s, perst_s;
    reg tog_q;
    reg [15:0] alive_cnt;
    always @(posedge clk) begin
        link_s <= {link_s[0], link_up_a};
        tog_s <= {tog_s[0], aclk_toggle_a};
        perst_s <= {perst_s[0], perst_n_a};
        tog_q <= tog_s[1];
        if (!rst_n) alive_cnt <= 16'd0;
        else if (tog_s[1] != tog_q) alive_cnt <= 16'hFFFF;
        else if (alive_cnt != 16'd0) alive_cnt <= alive_cnt - 16'd1;
    end
    wire link_up = link_s[1];
    wire aclk_alive = (alive_cnt != 16'd0);

    reg [31:0] host_db, cpu_db;
    reg        ien, ever_up;
    reg [31:0] host_wr, host_rd;
    reg [31:0] mbox [0:15];
    reg [31:0] wbase, wsize;
    assign win_base = wbase;
    assign win_size = wsize;

    wire h_mb = h_we && (h_addr[6:2] >= 5'd8) && (h_addr[6:2] < 5'd24);
    wire c_mb = c_we && (c_addr[6:2] >= 5'd8) && (c_addr[6:2] < 5'd24);
    wire [3:0] h_mi = h_addr[5:2] - 4'd8;
    wire [3:0] c_mi = c_addr[5:2] - 4'd8;
    wire h_db_set = h_we && h_addr[6:2] == 5'd2;
    wire c_db_clr = c_we && c_addr[6:2] == 5'd2;
    wire c_db_set = c_we && c_addr[6:2] == 5'd3;
    wire h_db_clr = h_we && h_addr[6:2] == 5'd3;

    always @(posedge clk) begin
        if (!rst_n) begin
            host_db <= 32'd0;
            cpu_db <= 32'd0;
            ien <= 1'b0;
            ever_up <= 1'b0;
            host_wr <= 32'd0;
            host_rd <= 32'd0;
            wbase <= 32'd0;
            wsize <= 32'd0;
        end else begin
            if (c_we && c_addr[6:2] == 5'd28) wbase <= c_wd;
            if (c_we && c_addr[6:2] == 5'd29) wsize <= c_wd;
            host_db <= (host_db & ~(c_db_clr ? c_wd : 32'd0)) | (h_db_set ? h_wd : 32'd0);
            cpu_db <= (cpu_db & ~(h_db_clr ? h_wd : 32'd0)) | (c_db_set ? c_wd : 32'd0);
            if (c_we && c_addr[6:2] == 5'd4) ien <= c_wd[0];
            if (link_up) ever_up <= 1'b1;
            else if (c_we && c_addr[6:2] == 5'd1 && c_wd[5]) ever_up <= 1'b0;
            if (h_we) host_wr <= host_wr + 32'd1;
            if (h_re) host_rd <= host_rd + 32'd1;
        end
        if (h_mb) mbox[h_mi] <= h_wd;
        if (c_mb) mbox[c_mi] <= c_wd;
    end

    wire [31:0] status = {26'd0, ever_up, |cpu_db, |host_db, perst_s[1], aclk_alive, link_up};

    function [31:0] rd(input [4:0] a, input [31:0] mb, input cpu);
        case (a)
            5'd0: rd = ID;
            5'd1: rd = status;
            5'd2: rd = host_db;
            5'd3: rd = cpu_db;
            5'd4: rd = {31'd0, ien};
            5'd5: rd = host_wr;
            5'd6: rd = host_rd;
            5'd28: rd = cpu ? wbase : 32'd0;
            5'd29: rd = cpu ? wsize : 32'd0;
            default: rd = (a >= 5'd8 && a < 5'd24) ? mb : 32'd0;
        endcase
    endfunction
    always @(posedge clk) begin
        h_rd <= rd(h_addr[6:2], mbox[h_addr[5:2] - 4'd8], 1'b0);
        c_rd <= rd(c_addr[6:2], mbox[c_addr[5:2] - 4'd8], 1'b1);
    end

    assign irq = ien && (|host_db);
    assign cpu_db_any = |cpu_db;
endmodule
