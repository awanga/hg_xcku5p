// SPDX-License-Identifier: MIT
// Board control registers (word offsets from the 4 KiB window):
//   0x00 LED     rw  [7:0] LED outputs
//   0x04 KEY     ro  [0] key pressed
//   0x08 STATUS  ro  [0] DDR4 calibration done  [1] DDR4 ui_clk reset deasserted
//   0x0C CPU_KHZ ro  CPU clock in kHz (parameter)
//   0x10 TICK    ro  free-running counter on clk (periph clock), for coarse timing
//   0x14 SCRATCH rw  32 bits
// Inputs from other clock domains are double-registered here.
module soc_regs #(
    parameter CPU_KHZ = 400000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [4:2]  addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    input  wire        re,
    output reg  [31:0] rdata,
    output reg  [7:0]  led,
    input  wire        key_in,
    input  wire        ddr_calib_in,
    input  wire        ddr_rst_n_in
);
    reg [31:0] scratch;
    reg [31:0] tick;
    (* ASYNC_REG = "TRUE" *) reg [2:0] key_s;
    (* ASYNC_REG = "TRUE" *) reg [2:0] calib_s;
    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_s;

    always @(posedge clk) begin
        key_s   <= {key_s[1:0], key_in};
        calib_s <= {calib_s[1:0], ddr_calib_in};
        rst_s   <= {rst_s[1:0], ddr_rst_n_in};
        tick    <= tick + 1'b1;
        if (!rst_n) begin
            led     <= 8'd0;
            scratch <= 32'd0;
        end else if (we) begin
            if (addr == 3'd0 && wstrb[0]) led <= wdata[7:0];
            if (addr == 3'd5) begin
                if (wstrb[0]) scratch[7:0]   <= wdata[7:0];
                if (wstrb[1]) scratch[15:8]  <= wdata[15:8];
                if (wstrb[2]) scratch[23:16] <= wdata[23:16];
                if (wstrb[3]) scratch[31:24] <= wdata[31:24];
            end
        end
        if (re) begin
            case (addr)
            3'd0: rdata <= {24'd0, led};
            3'd1: rdata <= {31'd0, key_s[2]};
            3'd2: rdata <= {30'd0, rst_s[2], calib_s[2]};
            3'd3: rdata <= CPU_KHZ;
            3'd4: rdata <= tick;
            3'd5: rdata <= scratch;
            default: rdata <= 32'd0;
            endcase
        end
    end
endmodule
