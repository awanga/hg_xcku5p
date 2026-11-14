// SPDX-License-Identifier: MIT
// AXI4-Lite slave to a simple word-register bus. One transaction at a time; reads win over writes.
// Contract (all outputs registered unless noted):
//   write: after AW and W are both seen, we pulses 1 cycle with addr/wdata/wstrb, then BVALID is held until BREADY.
//   read:  re pulses 1 cycle with addr; the backing store must present rdata valid 1 cycle after re (registered
//          read). RVALID is then held until RREADY. Responses are always OKAY.
module axil_simple #(
    parameter AW = 16
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [AW-1:0] s_awaddr,
    input  wire          s_awvalid,
    output wire          s_awready,
    input  wire [31:0]   s_wdata,
    input  wire [3:0]    s_wstrb,
    input  wire          s_wvalid,
    output wire          s_wready,
    output wire [1:0]    s_bresp,
    output reg           s_bvalid,
    input  wire          s_bready,
    input  wire [AW-1:0] s_araddr,
    input  wire          s_arvalid,
    output wire          s_arready,
    output wire [31:0]   s_rdata,
    output wire [1:0]    s_rresp,
    output reg           s_rvalid,
    input  wire          s_rready,

    output reg  [AW-1:0] addr,
    output reg           we,
    output reg  [31:0]   wdata,
    output reg  [3:0]    wstrb,
    output reg           re,
    input  wire [31:0]   rdata
);
    localparam IDLE = 3'd0, WR = 3'd1, BRSP = 3'd2, RD0 = 3'd3, RD1 = 3'd4, RRSP = 3'd5;
    reg [2:0]  state;
    reg [31:0] rdata_q;

    wire take_rd = s_arvalid;
    wire take_wr = s_awvalid && s_wvalid && !s_arvalid;

    assign s_arready = (state == IDLE) && take_rd;
    assign s_awready = (state == IDLE) && take_wr;
    assign s_wready  = (state == IDLE) && take_wr;
    assign s_bresp   = 2'b00;
    assign s_rresp   = 2'b00;
    assign s_rdata   = rdata_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            s_bvalid <= 1'b0;
            s_rvalid <= 1'b0;
            we <= 1'b0;
            re <= 1'b0;
        end else begin
            we <= 1'b0;
            re <= 1'b0;
            case (state)
            IDLE: begin
                if (take_rd) begin
                    addr  <= s_araddr;
                    re    <= 1'b1;
                    state <= RD0;
                end else if (take_wr) begin
                    addr  <= s_awaddr;
                    wdata <= s_wdata;
                    wstrb <= s_wstrb;
                    we    <= 1'b1;
                    state <= WR;
                end
            end
            WR: begin
                s_bvalid <= 1'b1;
                state    <= BRSP;
            end
            BRSP: begin
                if (s_bready) begin
                    s_bvalid <= 1'b0;
                    state    <= IDLE;
                end
            end
            RD0: state <= RD1;
            RD1: begin
                rdata_q  <= rdata;
                s_rvalid <= 1'b1;
                state    <= RRSP;
            end
            RRSP: begin
                if (s_rready) begin
                    s_rvalid <= 1'b0;
                    state    <= IDLE;
                end
            end
            default: state <= IDLE;
            endcase
        end
    end
endmodule
