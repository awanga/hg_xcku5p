// SPDX-License-Identifier: MIT
// Behavioural models of the SpinalHDL memory blackboxes emitted by the VexiiRiscv SoC generator
// (spinalConfig.addStandardMemBlackboxing). Port and parameter lists match the generated netlists;
// read-under-write is "dontCare" in the netlists, so read-first is used. Vivado infers LUTRAM/BRAM from these.

// One write port, one asynchronous (combinational) read port.
module Ram_1w_1ra #(
    parameter integer wordCount = 0,
    parameter integer wordWidth = 0,
    parameter technology = "auto",
    parameter readUnderWrite = "dontCare",
    parameter integer wrAddressWidth = 0,
    parameter integer wrDataWidth = 0,
    parameter integer wrMaskWidth = 1,
    parameter wrMaskEnable = 1'b0,
    parameter integer rdAddressWidth = 0,
    parameter integer rdDataWidth = 0
) (
    input  wire                      clk,
    input  wire                      wr_en,
    input  wire [wrMaskWidth-1:0]    wr_mask,
    input  wire [wrAddressWidth-1:0] wr_addr,
    input  wire [wrDataWidth-1:0]    wr_data,
    input  wire [rdAddressWidth-1:0] rd_addr,
    output wire [rdDataWidth-1:0]    rd_data
);
    reg [wrDataWidth-1:0] ram_block [0:wordCount-1];
    integer i;

    always @(posedge clk) begin
        if (wr_en) begin
            if (wrMaskEnable) begin
                for (i = 0; i < wrMaskWidth; i = i + 1)
                    if (wr_mask[i])
                        ram_block[wr_addr][i*(wrDataWidth/wrMaskWidth) +: (wrDataWidth/wrMaskWidth)] <=
                            wr_data[i*(wrDataWidth/wrMaskWidth) +: (wrDataWidth/wrMaskWidth)];
            end else begin
                ram_block[wr_addr] <= wr_data;
            end
        end
    end

    assign rd_data = ram_block[rd_addr];
endmodule

// One write port, one synchronous read port (rdLatency 1, or 2 with an output register enabled by rd_dataEn).
module Ram_1w_1rs #(
    parameter integer wordCount = 0,
    parameter integer wordWidth = 0,
    parameter clockCrossing = 1'b0,
    parameter technology = "auto",
    parameter readUnderWrite = "dontCare",
    parameter integer wrAddressWidth = 0,
    parameter integer wrDataWidth = 0,
    parameter integer wrMaskWidth = 1,
    parameter wrMaskEnable = 1'b0,
    parameter integer rdAddressWidth = 0,
    parameter integer rdDataWidth = 0,
    parameter integer rdLatency = 1
) (
    input  wire                      wr_clk,
    input  wire                      wr_en,
    input  wire [wrMaskWidth-1:0]    wr_mask,
    input  wire [wrAddressWidth-1:0] wr_addr,
    input  wire [wrDataWidth-1:0]    wr_data,
    input  wire                      rd_clk,
    input  wire                      rd_en,
    input  wire [rdAddressWidth-1:0] rd_addr,
    input  wire                      rd_dataEn,
    output wire [rdDataWidth-1:0]    rd_data
);
    reg [wrDataWidth-1:0] ram_block [0:wordCount-1];
    reg [rdDataWidth-1:0] rd_q;
    reg [rdDataWidth-1:0] rd_q2;
    integer i;

    always @(posedge wr_clk) begin
        if (wr_en) begin
            if (wrMaskEnable) begin
                for (i = 0; i < wrMaskWidth; i = i + 1)
                    if (wr_mask[i])
                        ram_block[wr_addr][i*(wrDataWidth/wrMaskWidth) +: (wrDataWidth/wrMaskWidth)] <=
                            wr_data[i*(wrDataWidth/wrMaskWidth) +: (wrDataWidth/wrMaskWidth)];
            end else begin
                ram_block[wr_addr] <= wr_data;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (rd_en) rd_q <= ram_block[rd_addr];
        if (rd_dataEn) rd_q2 <= rd_q;
    end

    assign rd_data = (rdLatency == 2) ? rd_q2 : rd_q;
endmodule

// Same as Ram_1w_1rs but mapped to UltraRAM; selected for the L2 data banks by fpga/scripts/cpu/uram_l2.sh.
module Ram_1w_1rs_ultra #(
    parameter integer wordCount = 0,
    parameter integer wordWidth = 0,
    parameter clockCrossing = 1'b0,
    parameter technology = "auto",
    parameter readUnderWrite = "dontCare",
    parameter integer wrAddressWidth = 0,
    parameter integer wrDataWidth = 0,
    parameter integer wrMaskWidth = 1,
    parameter wrMaskEnable = 1'b0,
    parameter integer rdAddressWidth = 0,
    parameter integer rdDataWidth = 0,
    parameter integer rdLatency = 1
) (
    input  wire                      wr_clk,
    input  wire                      wr_en,
    input  wire [wrMaskWidth-1:0]    wr_mask,
    input  wire [wrAddressWidth-1:0] wr_addr,
    input  wire [wrDataWidth-1:0]    wr_data,
    input  wire                      rd_clk,
    input  wire                      rd_en,
    input  wire [rdAddressWidth-1:0] rd_addr,
    input  wire                      rd_dataEn,
    output wire [rdDataWidth-1:0]    rd_data
);
    (* ram_style = "ultra" *) reg [wrDataWidth-1:0] ram_block [0:wordCount-1];
    reg [rdDataWidth-1:0] rd_q;
    reg [rdDataWidth-1:0] rd_q2;
    integer i;

    always @(posedge wr_clk) begin
        if (wr_en) begin
            if (wrMaskEnable) begin
                for (i = 0; i < wrMaskWidth; i = i + 1)
                    if (wr_mask[i])
                        ram_block[wr_addr][i*(wrDataWidth/wrMaskWidth) +: (wrDataWidth/wrMaskWidth)] <=
                            wr_data[i*(wrDataWidth/wrMaskWidth) +: (wrDataWidth/wrMaskWidth)];
            end else begin
                ram_block[wr_addr] <= wr_data;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (rd_en) rd_q <= ram_block[rd_addr];
        if (rd_dataEn) rd_q2 <= rd_q;
    end

    assign rd_data = (rdLatency == 2) ? rd_q2 : rd_q;
endmodule
