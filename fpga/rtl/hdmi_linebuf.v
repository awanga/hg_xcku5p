// SPDX-License-Identifier: MIT
// Two-line buffer: one write port (AXI clock), one registered read port (pixel clock). Inferred as block RAM; no read-during-write guarantee,
// the fetcher and the scan-out never touch the same half at the same time.
module hdmi_linebuf (
    input  wire        wclk,
    input  wire        we,
    input  wire [8:0]  waddr,
    input  wire [63:0] wdata,
    input  wire        rclk,
    input  wire [8:0]  raddr,
    output reg  [63:0] rdata
);
    reg [63:0] mem[0:511];
    always @(posedge wclk) if (we) mem[waddr] <= wdata;
    always @(posedge rclk) rdata <= mem[raddr];
endmodule
