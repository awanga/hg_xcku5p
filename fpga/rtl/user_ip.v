// SPDX-License-Identifier: MIT
// Placeholder for a future function block on the CPU-less PCIe card (card_top): a 16 KiB AXI4-Lite window (BAR0 + 0x4000, rig 0xF8004000).
// Replace this module, keeping its ports, with the register interface of the new IP (for example OpenMLA). Today no IP is attached: every read returns 0
// and every write is ignored, which a host driver can tell apart from the crossbar's DECERR on an unmapped address.
// Contract: same AXI4-Lite subset as card_regs (axil_simple: one transaction at a time, OKAY responses, read data one cycle after the address).
// Windows larger than 16 KiB do not fit BAR0 (64 KiB, shared with card_regs, user_regs and pcie_regs); bulk data goes through the DMA path to DDR4 instead.
// The small control/status/kick/event/interrupt file next to it is user_regs (BAR0 + 0x2000); use it for a few control bits and an interrupt, and this window for a real register map.
module user_ip (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [13:0]  s_awaddr,
    input  wire         s_awvalid,
    output wire         s_awready,
    input  wire [31:0]  s_wdata,
    input  wire [3:0]   s_wstrb,
    input  wire         s_wvalid,
    output wire         s_wready,
    output wire [1:0]   s_bresp,
    output wire         s_bvalid,
    input  wire         s_bready,
    input  wire [13:0]  s_araddr,
    input  wire         s_arvalid,
    output wire         s_arready,
    output wire [31:0]  s_rdata,
    output wire [1:0]   s_rresp,
    output wire         s_rvalid,
    input  wire         s_rready
);
    /* verilator lint_off UNUSEDSIGNAL */
    wire [13:0] addr;
    wire        we, re;
    wire [31:0] wdata;
    wire [3:0]  wstrb;
    /* verilator lint_on UNUSEDSIGNAL */

    axil_simple #(.AW(14)) u_bus (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .addr(addr), .we(we), .wdata(wdata), .wstrb(wstrb), .re(re), .rdata(32'd0));
endmodule
