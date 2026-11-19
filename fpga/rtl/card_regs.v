// SPDX-License-Identifier: MIT
// Identity and status registers of the CPU-less PCIe card build (card_top). AXI4-Lite slave (per_clk) through axil_simple; reads of unlisted words give 0,
// writes to read-only words are ignored. The host sees this block at BAR0 + 0x1000 and the UART rig at 0xF8001000.
//   0x00 ID        RO  0x43415244 ("CARD")
//   0x04 LAYOUT    RO  register layout version (1)
//   0x08 VERSION   RO  {8'd0, major, minor, patch} of the release the build came from (parameter)
//   0x0C BUILD     RO  short source commit id (parameter, 0 if unknown)
//   0x10 PCI_ID    RO  {device ID, vendor ID} the PCIe core was built with (fpga/pcie_identity.cfg); the host compares them with its config space
//   0x14 PCI_CLASS RO  {class code[23:0], revision ID}
//   0x18 PCI_SUBSYS RO {subsystem ID, subsystem vendor ID}
//   0x1C CAPS      RO  bit0 DDR4, bit1 PCIe endpoint, bit2 UART2 rig, bit3 user register window (user_regs at 0x2000), bit4 board peripherals kept (0 here)
//   0x20 STATUS    RO  bit0 DDR4 calibration complete, bit1 KEY_PL0 pressed
//   0x24 DDR_MIB   RO  DDR4 capacity in MiB (parameter)
//   0x28 UPTIME    RO  seconds since reset (per_clk cycles counted against CLK_HZ)
//   0x2C SCRATCH   RW  free for the host and the rig
//   0x30 LED       RW  bits 7:0 drive the user LEDs (reset 0)
// Status inputs come from the DDR4 user clock and the key pin: two-flop synchronisers here.
module card_regs #(
    parameter [31:0] VERSION   = 32'd0,
    parameter [31:0] BUILD     = 32'd0,
    parameter [31:0] PCI_ID    = 32'h903410EE,
    parameter [31:0] PCI_CLASS = 32'h05800000,
    parameter [31:0] PCI_SUBSYS = 32'h000710EE,
    parameter [31:0] DDR_MIB   = 32'd1024,
    parameter [31:0] CLK_HZ    = 32'd100000000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] s_awaddr,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,
    input  wire [11:0] s_araddr,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rvalid,
    input  wire        s_rready,
    input  wire        calib_in,
    input  wire        key_in,
    output wire [7:0]  led
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

    (* ASYNC_REG = "TRUE" *) reg [1:0] calib_s, key_s;
    reg [31:0] scratch;
    reg [7:0]  led_q;
    reg [31:0] sec, tick;
    assign led = led_q;

    always @(posedge clk) begin
        calib_s <= {calib_s[0], calib_in};
        key_s   <= {key_s[0], key_in};
        if (!rst_n) begin
            scratch <= 32'd0;
            led_q <= 8'd0;
            sec <= 32'd0;
            tick <= 32'd0;
        end else begin
            if (tick == CLK_HZ - 32'd1) begin
                tick <= 32'd0;
                sec <= sec + 32'd1;
            end else tick <= tick + 32'd1;
            if (we && addr[11:2] == 10'h0B) begin
                if (wstrb[0]) scratch[7:0] <= wdata[7:0];
                if (wstrb[1]) scratch[15:8] <= wdata[15:8];
                if (wstrb[2]) scratch[23:16] <= wdata[23:16];
                if (wstrb[3]) scratch[31:24] <= wdata[31:24];
            end
            if (we && addr[11:2] == 10'h0C && wstrb[0]) led_q <= wdata[7:0];
        end
        if (re) begin
            case (addr[11:2])
            10'h00: rdata <= 32'h43415244;
            10'h01: rdata <= 32'd1;
            10'h02: rdata <= VERSION;
            10'h03: rdata <= BUILD;
            10'h04: rdata <= PCI_ID;
            10'h05: rdata <= PCI_CLASS;
            10'h06: rdata <= PCI_SUBSYS;
            10'h07: rdata <= 32'h0000000F;
            10'h08: rdata <= {30'd0, key_s[1], calib_s[1]};
            10'h09: rdata <= DDR_MIB;
            10'h0A: rdata <= sec;
            10'h0B: rdata <= scratch;
            10'h0C: rdata <= {24'd0, led_q};
            default: rdata <= 32'd0;
            endcase
        end
    end
endmodule
