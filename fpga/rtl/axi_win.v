// SPDX-License-Identifier: MIT
// AXI4 window filter: forwards a burst only if all of its bytes lie inside [win_base, win_base + win_size); any other burst is answered
// with DECERR (write data is absorbed, read data is zero, one beat per requested beat) and never reaches the master port.
// win_size = 0 closes the window (no burst fits in zero bytes). One burst per direction at a time (the next address is accepted after the previous response), which keeps the
// decode simple and the error path unambiguous; the read and write directions run independently.
// A burst's start address must be inside the window and the last byte (start + (len+1) << size - 1) must be inside too; INCR bursts only are
// checked exactly (FIXED/WRAP stay within one burst-sized region, which the same check covers). `s_awhi`/`s_arhi` flag a nonzero upper address
// (the PCIe side has 64-bit addresses, the SoC side 32): such a burst is an error.
module axi_win #(
    parameter DW = 64,
    parameter IDW = 4
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire [31:0]     win_base,
    input  wire [31:0]     win_size,
    // slave side (from the PCIe core)
    input  wire [IDW-1:0]  s_awid,
    input  wire [31:0]     s_awaddr,
    input  wire            s_awhi,
    input  wire [7:0]      s_awlen,
    input  wire [2:0]      s_awsize,
    input  wire [1:0]      s_awburst,
    input  wire            s_awvalid,
    output reg             s_awready,
    input  wire [DW-1:0]   s_wdata,
    input  wire [DW/8-1:0] s_wstrb,
    input  wire            s_wlast,
    input  wire            s_wvalid,
    output reg             s_wready,
    output reg  [IDW-1:0]  s_bid,
    output reg  [1:0]      s_bresp,
    output reg             s_bvalid,
    input  wire            s_bready,
    input  wire [IDW-1:0]  s_arid,
    input  wire [31:0]     s_araddr,
    input  wire            s_arhi,
    input  wire [7:0]      s_arlen,
    input  wire [2:0]      s_arsize,
    input  wire [1:0]      s_arburst,
    input  wire            s_arvalid,
    output reg             s_arready,
    output reg  [IDW-1:0]  s_rid,
    output reg  [DW-1:0]   s_rdata,
    output reg  [1:0]      s_rresp,
    output reg             s_rlast,
    output reg             s_rvalid,
    input  wire            s_rready,
    // master side (towards the SoC memory)
    output reg  [IDW-1:0]  m_awid,   // always 0: bursts are serialised, the response id is the one latched from the slave side
    output reg  [31:0]     m_awaddr,
    output reg  [7:0]      m_awlen,
    output reg  [2:0]      m_awsize,
    output reg  [1:0]      m_awburst,
    output reg             m_awvalid,
    input  wire            m_awready,
    output reg  [DW-1:0]   m_wdata,
    output reg  [DW/8-1:0] m_wstrb,
    output reg             m_wlast,
    output reg             m_wvalid,
    input  wire            m_wready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [IDW-1:0]  m_bid,
    input  wire [1:0]      m_bresp,
    input  wire            m_bvalid,
    output reg             m_bready,
    output reg  [IDW-1:0]  m_arid,
    output reg  [31:0]     m_araddr,
    output reg  [7:0]      m_arlen,
    output reg  [2:0]      m_arsize,
    output reg  [1:0]      m_arburst,
    output reg             m_arvalid,
    input  wire            m_arready,
    input  wire [IDW-1:0]  m_rid,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [DW-1:0]   m_rdata,
    input  wire [1:0]      m_rresp,
    input  wire            m_rlast,
    input  wire            m_rvalid,
    output reg             m_rready
);
    // The window check is pipelined over three cycles after an address is captured (offset and byte count, then the end offset, then the compare): the
    // 33-bit arithmetic does not fit one 3 ns cycle. `*_stage` counts 0 (idle) .. 3 (result valid in *_ok). A burst's last byte must be inside the
    // window: end = (addr - base) + bytes <= win_size, with addr >= base.
    reg [32:0] w_off, r_off, w_end, r_end;
    reg [15:0] w_bytes, r_bytes;
    reg        w_ge, r_ge, w_hi, r_hi, w_ok, r_ok;
    reg [1:0]  w_stage, r_stage;

    localparam [1:0] DECERR = 2'b11;


    // check pipeline: restarts whenever the FSM is waiting in WC / RC (stage 0 while capturing); inputs come from the captured m_* address registers
    always @(posedge clk) begin
        if (wst == WC) begin
            case (w_stage)
                2'd0: begin
                    w_off <= {1'b0, m_awaddr} - {1'b0, win_base};
                    w_bytes <= ({8'd0, m_awlen} + 16'd1) << m_awsize;
                    w_stage <= 2'd1;
                end
                2'd1: begin
                    w_ge <= !w_off[32];
                    w_end <= w_off + {17'd0, w_bytes};
                    w_stage <= 2'd2;
                end
                2'd2: begin
                    w_ok <= !w_hi && w_ge && ({1'b0, win_size} >= w_end);
                    w_stage <= 2'd3;
                end
                default: ;
            endcase
        end else w_stage <= 2'd0;
        if (rst == RC) begin
            case (r_stage)
                2'd0: begin
                    r_off <= {1'b0, m_araddr} - {1'b0, win_base};
                    r_bytes <= ({8'd0, m_arlen} + 16'd1) << m_arsize;
                    r_stage <= 2'd1;
                end
                2'd1: begin
                    r_ge <= !r_off[32];
                    r_end <= r_off + {17'd0, r_bytes};
                    r_stage <= 2'd2;
                end
                2'd2: begin
                    r_ok <= !r_hi && r_ge && ({1'b0, win_size} >= r_end);
                    r_stage <= 2'd3;
                end
                default: ;
            endcase
        end else r_stage <= 2'd0;
    end

    // ---------------- write direction
    localparam WI = 3'd0, WA = 3'd1, WD = 3'd2, WB = 3'd3, WX = 3'd4, WE = 3'd5, WC = 3'd6;
    reg [2:0] wst;
    reg [IDW-1:0] bid_q;
    always @(posedge clk) begin
        if (!rst_n) begin
            wst <= WI;
            s_awready <= 1'b0;
            m_awvalid <= 1'b0;
        end else begin
            s_awready <= 1'b0;
            case (wst)
                WI: begin
                    if (s_awvalid && !s_awready) begin
                        s_awready <= 1'b1;
                        m_awaddr <= s_awaddr;
                        m_awlen <= s_awlen;
                        m_awsize <= s_awsize;
                        m_awburst <= s_awburst;
                        bid_q <= s_awid;
                        w_hi <= s_awhi;
                        wst <= WC;
                    end
                end
                WC: if (w_stage == 2'd3) begin
                    if (w_ok) begin
                        m_awvalid <= 1'b1;
                        wst <= WA;
                    end else wst <= WX;
                end
                WA: if (m_awvalid && m_awready) begin
                    m_awvalid <= 1'b0;
                    wst <= WD;
                end
                WD: if (s_wvalid && m_wready && s_wlast) wst <= WB;
                WB: if (m_bvalid && s_bready) wst <= WI;
                WX: if (s_wvalid && s_wlast) wst <= WE;   // absorb the data of a refused burst
                WE: if (s_bready) wst <= WI;
                default: wst <= WI;
            endcase
        end
    end
    always @* begin
        m_wdata = s_wdata;
        m_wstrb = s_wstrb;
        m_wlast = s_wlast;
        m_wvalid = (wst == WD) && s_wvalid;
        s_wready = (wst == WD && m_wready) || (wst == WX);
        m_bready = (wst == WB) && s_bready;
        s_bresp = (wst == WE) ? DECERR : m_bresp;
        m_awid = {IDW{1'b0}};
        s_bid = bid_q;
        s_bvalid = (wst == WB) ? m_bvalid : (wst == WE);
    end

    // ---------------- read direction
    localparam RI = 3'd0, RA = 3'd1, RD = 3'd2, RE = 3'd3, RC = 3'd4;
    reg [2:0] rst;
    reg [7:0] rcnt;
    reg [IDW-1:0] eid;
    reg [7:0] elen;
    always @(posedge clk) begin
        if (!rst_n) begin
            rst <= RI;
            s_arready <= 1'b0;
            m_arvalid <= 1'b0;
        end else begin
            s_arready <= 1'b0;
            case (rst)
                RI: begin
                    if (s_arvalid && !s_arready) begin
                        s_arready <= 1'b1;
                        m_araddr <= s_araddr;
                        m_arlen <= s_arlen;
                        m_arsize <= s_arsize;
                        m_arburst <= s_arburst;
                        eid <= s_arid;
                        elen <= s_arlen;
                        rcnt <= 8'd0;
                        r_hi <= s_arhi;
                        rst <= RC;
                    end
                end
                RC: if (r_stage == 2'd3) begin
                    if (r_ok) begin
                        m_arvalid <= 1'b1;
                        rst <= RA;
                    end else rst <= RE;
                end
                RA: if (m_arvalid && m_arready) begin
                    m_arvalid <= 1'b0;
                    rst <= RD;
                end
                RD: if (m_rvalid && s_rready && m_rlast) rst <= RI;
                RE: if (s_rready) begin
                    rcnt <= rcnt + 8'd1;
                    if (rcnt == elen) rst <= RI;
                end
                default: rst <= RI;
            endcase
        end
    end
    always @* begin
        m_arid = {IDW{1'b0}};
        if (rst == RE) begin
            s_rid = eid;
            s_rdata = {DW{1'b0}};
            s_rresp = DECERR;
            s_rlast = (rcnt == elen);
            s_rvalid = 1'b1;
            m_rready = 1'b0;
        end else begin
            s_rid = eid;
            s_rdata = m_rdata;
            s_rresp = m_rresp;
            s_rlast = m_rlast;
            s_rvalid = (rst == RD) && m_rvalid;
            m_rready = (rst == RD) && s_rready;
        end
    end
endmodule
