// SPDX-License-Identifier: MIT
// Copy engine: reads a byte range from an AXI4-Lite source (the LiteEth packet buffer window, 32-bit reads, one at a time)
// and writes it to any byte address through single-beat 64-bit AXI4 writes (the coherent DMA port of the SoC, so the CPU
// caches need no maintenance). One job at a time, byte-serial inner loop: the source read (~190 ns per word through the
// peripheral clock converter and the LiteEth wishbone bridge) dominates, so no burst or lane-shifting logic is needed.
//
// Registers (word offsets, byte addresses on s_*; unused address bits ignored):
//   0x00 SRC   source byte address, bits [1:0] must be 0 (a word-aligned source is the caller's contract)
//   0x04 DST   destination byte address, any alignment
//   0x08 LEN   bytes to copy, 0 completes immediately
//   0x0C CTRL  write: bit0 = start (ignored while busy), bit1 = clear DONE, bit2 = clear ERR
//              read:  bit0 = BUSY, bit1 = DONE, bit2 = ERR
//   0x10 IEN   bit0 = interrupt enable
// irq = DONE & IEN, a level held until the CPU clears DONE (the PLIC gateway loses pulses that arrive while an interrupt
// is in flight). A non-OKAY read or write response sets ERR, abandons the job and still sets DONE.
// Write channel contract: AW and W are issued together (either may be accepted first), awlen = 0, wlast = 1, one B per beat.
module eth_dma (
    input  wire        clk,
    input  wire        rst_n,
    // register slave (AXI4-Lite)
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
    // source master (AXI4-Lite, read only)
    output reg  [31:0] m_araddr,
    output reg         m_arvalid,
    input  wire        m_arready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rvalid,
    output reg         m_rready,
    // destination master (AXI4 write, single beat)
    output reg  [31:0] m_awaddr,
    output reg         m_awvalid,
    input  wire        m_awready,
    output reg  [63:0] m_wdata,
    output reg  [7:0]  m_wstrb,
    output reg         m_wvalid,
    input  wire        m_wready,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output reg         m_bready,
    output wire        irq
);
    localparam IDLE = 3'd0, AR = 3'd1, RD = 3'd2, BYTE = 3'd3, WR = 3'd4, WRB = 3'd5, FIN = 3'd6;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [4:0]  reg_addr;   // bits [1:0] and reg_re unused: registers are word-addressed, reads are registered every cycle
    wire        reg_we, reg_re;
    wire [3:0]  reg_wstrb;  // only byte 0 is decoded: all registers are written whole by the driver
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] reg_wdata;
    reg  [31:0] reg_rdata;

    reg [2:0]  state;
    reg [31:0] src, dst, len, left;
    reg [31:0] word;
    reg [2:0]  pos;
    reg [2:0]  idx;
    reg        done, err, ien;

    wire busy = (state != IDLE);
    assign irq = done & ien;

    axil_simple #(.AW(5)) u_regs (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .addr(reg_addr), .we(reg_we), .wdata(reg_wdata), .wstrb(reg_wstrb), .re(reg_re), .rdata(reg_rdata));

    // The engine's own address-less read mux; axil_simple presents rdata one cycle after re.
    always @(posedge clk) begin
        case (reg_addr[4:2])
            3'd0: reg_rdata <= src;
            3'd1: reg_rdata <= dst;
            3'd2: reg_rdata <= len;
            3'd3: reg_rdata <= {29'd0, err, done, busy};
            default: reg_rdata <= {31'd0, ien};
        endcase
    end

    wire [2:0]  n_idx = idx + 3'd1;
    wire [31:0] n_left = left - 32'd1;
    wire        flush = (pos == 3'd7) || (n_left == 32'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            err <= 1'b0;
            ien <= 1'b0;
            m_arvalid <= 1'b0;
            m_rready <= 1'b0;
            m_awvalid <= 1'b0;
            m_wvalid <= 1'b0;
            m_bready <= 1'b0;
        end else begin
            if (reg_we && reg_addr[4:2] == 3'd4 && reg_wstrb[0]) ien <= reg_wdata[0];
            if (reg_we && reg_addr[4:2] == 3'd3 && reg_wstrb[0]) begin
                if (reg_wdata[1]) done <= 1'b0;
                if (reg_wdata[2]) err <= 1'b0;
            end
            if (reg_we && !busy && reg_wstrb[0]) begin
                case (reg_addr[4:2])
                    3'd0: src <= reg_wdata;
                    3'd1: dst <= reg_wdata;
                    3'd2: len <= reg_wdata;
                    default: ;
                endcase
            end
            case (state)
                IDLE: begin
                    if (reg_we && reg_addr[4:2] == 3'd3 && reg_wstrb[0] && reg_wdata[0]) begin
                        left <= len;
                        pos <= dst[2:0];
                        m_awaddr <= {dst[31:3], 3'd0};
                        m_wstrb <= 8'd0;
                        m_wdata <= 64'd0;
                        idx <= 3'd4;
                        state <= (len == 32'd0) ? FIN : AR;
                        m_araddr <= src;
                        m_arvalid <= (len != 32'd0);
                    end
                end
                AR: begin
                    if (m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready <= 1'b1;
                        state <= RD;
                    end
                end
                RD: begin
                    if (m_rvalid) begin
                        m_rready <= 1'b0;
                        m_araddr <= m_araddr + 32'd4;
                        if (m_rresp != 2'b00) begin
                            err <= 1'b1;
                            state <= FIN;
                        end else begin
                            word <= m_rdata;
                            idx <= 3'd0;
                            state <= BYTE;
                        end
                    end
                end
                BYTE: begin
                    m_wdata[{pos, 3'd0} +: 8] <= word[{idx[1:0], 3'd0} +: 8];
                    m_wstrb[pos] <= 1'b1;
                    pos <= pos + 3'd1;
                    idx <= n_idx;
                    left <= n_left;
                    if (flush) begin
                        m_awvalid <= 1'b1;
                        m_wvalid <= 1'b1;
                        state <= WR;
                    end else if (n_idx == 3'd4) begin
                        m_arvalid <= 1'b1;
                        state <= AR;
                    end
                end
                WR: begin
                    if (m_awvalid && m_awready) m_awvalid <= 1'b0;
                    if (m_wvalid && m_wready) m_wvalid <= 1'b0;
                    if ((!m_awvalid || m_awready) && (!m_wvalid || m_wready)) begin
                        m_bready <= 1'b1;
                        state <= WRB;
                    end
                end
                WRB: begin
                    if (m_bvalid) begin
                        m_bready <= 1'b0;
                        m_awaddr <= m_awaddr + 32'd8;
                        m_wstrb <= 8'd0;
                        pos <= 3'd0;
                        if (m_bresp != 2'b00) begin
                            err <= 1'b1;
                            state <= FIN;
                        end else if (left == 32'd0) state <= FIN;
                        else if (idx == 3'd4) begin
                            m_arvalid <= 1'b1;
                            state <= AR;
                        end else state <= BYTE;
                    end
                end
                FIN: begin
                    done <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
