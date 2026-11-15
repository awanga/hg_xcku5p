// SPDX-License-Identifier: MIT
// Logical PCIe device for the CPU-as-root-complex variant (decision 0008, stage 1). It stands in for the PCIe hard block as the Linux generic ECAM host
// bridge sees it: a 2 MiB AXI4-Lite slave window at BASE, the lower 1 MiB being the ECAM of bus 0 and the upper 1 MiB the BAR (memory) window.
//   ECAM  addr[19:12] = device/function, addr[11:2] = dword. Only 00:00.0 exists; every other function reads all-ones and drops writes (a PCI master abort).
//   00:00.0 type 0 header: 10EE:9034 (the XDMA IDs), class 05 80 00, subsystem 10EE:0007, BAR0 = 64 KiB memory (bits 31:16 settable, read-back
//           mask FFFF0000 for sizing), command = memory enable (bit1), bus master (bit2), INTx disable (bit10); status bit3 = INTx pending;
//           cache line size and interrupt line are plain read/write bytes; interrupt pin = INTA; no capability list, BAR1-5 and the ROM read 0.
//   BAR0 accesses are forwarded as AXI4-Lite transactions (offset addr[6:0]) to the register block the firmware under test serves (pcie_regs h_* port),
//   only while memory enable is set and BAR0 equals the accessed address; any other BAR-window access is a master abort (reads all-ones, writes dropped).
// Every response is OKAY. One write and one read can be in flight (separate state machines); each completes before the next of its kind is accepted.
// `intx_pending` is the device's interrupt condition (a level); `intx` = pending and INTx not disabled in the command register.
module vpcie #(
    parameter [31:0] BASE = 32'hF9000000
) (
    input  wire        clk,
    input  wire        rst_n,
    // slave window (host bridge)
    input  wire [20:0] s_awaddr,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,
    input  wire [20:0] s_araddr,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rvalid,
    input  wire        s_rready,
    // BAR0 target (pcie_regs host window)
    output wire [6:0]  m_awaddr,
    output wire        m_awvalid,
    input  wire        m_awready,
    output wire [31:0] m_wdata,
    output wire [3:0]  m_wstrb,
    output wire        m_wvalid,
    input  wire        m_wready,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready,
    output wire [6:0]  m_araddr,
    output wire        m_arvalid,
    input  wire        m_arready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rvalid,
    output wire        m_rready,
    input  wire        intx_pending,
    output wire        intx
);
    // configuration registers
    reg        cmd_mem, cmd_bm, cmd_intxd;
    reg [7:0]  clsz, iline;
    reg [15:0] bar0;

    assign intx = intx_pending & ~cmd_intxd;

    // ---------------------------------------------------------------- write
    localparam [2:0] W_AW = 3'd0, W_W = 3'd1, W_X = 3'd2, W_F = 3'd3, W_B = 3'd4;
    reg [2:0]  ws;
    reg [20:0] wa;
    reg [31:0] wd;
    reg [3:0]  wb;
    reg        maw, mw;
    // m_bresp and the read response codes are not forwarded: the host bridge sees OKAY for everything
    /* verilator lint_off UNUSEDSIGNAL */
    wire [1:0] unused_resp = m_bresp ^ m_rresp;
    /* verilator lint_on UNUSEDSIGNAL */

    wire w_cfg    = ~wa[20];
    wire w_cfg_f0 = w_cfg && (wa[19:12] == 8'd0);
    wire w_hit    = wa[20] && cmd_mem && (bar0 == {BASE[31:21], wa[20:16]});

    assign s_awready = (ws == W_AW);
    assign s_wready  = (ws == W_W);
    assign s_bvalid  = (ws == W_B);
    assign s_bresp   = 2'b00;
    assign m_awaddr  = wa[6:0];
    assign m_awvalid = maw;
    assign m_wdata   = wd;
    assign m_wstrb   = wb;
    assign m_wvalid  = mw;
    assign m_bready  = (ws == W_F) && !maw && !mw;

    always @(posedge clk) begin
        if (!rst_n) begin
            ws <= W_AW;
            maw <= 1'b0;
            mw <= 1'b0;
            cmd_mem <= 1'b0;
            cmd_bm <= 1'b0;
            cmd_intxd <= 1'b0;
            clsz <= 8'd0;
            iline <= 8'd0;
            bar0 <= 16'd0;
        end else begin
            case (ws)
            W_AW: if (s_awvalid) begin
                wa <= s_awaddr;
                ws <= W_W;
            end
            W_W: if (s_wvalid) begin
                wd <= s_wdata;
                wb <= s_wstrb;
                ws <= W_X;
            end
            W_X: begin
                ws <= W_B;
                if (w_cfg_f0) begin
                    case (wa[11:2])
                    10'h01: begin   // command; the status half is read-only here
                        if (wb[0]) begin
                            cmd_mem <= wd[1];
                            cmd_bm <= wd[2];
                        end
                        if (wb[1]) cmd_intxd <= wd[10];
                    end
                    10'h03: if (wb[0]) clsz <= wd[7:0];
                    10'h04: begin   // BAR0: 64 KiB, bits 15:0 read-only
                        if (wb[2]) bar0[7:0] <= wd[23:16];
                        if (wb[3]) bar0[15:8] <= wd[31:24];
                    end
                    10'h0F: if (wb[0]) iline <= wd[7:0];
                    default: ;
                    endcase
                end else if (w_hit) begin
                    maw <= 1'b1;
                    mw <= 1'b1;
                    ws <= W_F;
                end
            end
            W_F: begin
                if (maw && m_awready) maw <= 1'b0;
                if (mw && m_wready) mw <= 1'b0;
                if (m_bready && m_bvalid) ws <= W_B;
            end
            W_B: if (s_bready) ws <= W_AW;
            default: ws <= W_AW;
            endcase
        end
    end

    // ---------------------------------------------------------------- read
    localparam [2:0] R_AR = 3'd0, R_X = 3'd1, R_F = 3'd2, R_R = 3'd3;
    reg [2:0]  rs;
    reg [20:0] ra;
    reg [31:0] rd;
    reg        mar;

    wire r_cfg    = ~ra[20];
    wire r_cfg_f0 = r_cfg && (ra[19:12] == 8'd0);
    wire r_hit    = ra[20] && cmd_mem && (bar0 == {BASE[31:21], ra[20:16]});

    reg [31:0] cfg_q;
    always @* begin
        case (ra[11:2])
        10'h00: cfg_q = 32'h903410EE;
        10'h01: cfg_q = {12'd0, intx_pending, 3'd0, 5'd0, cmd_intxd, 7'd0, cmd_bm, cmd_mem, 1'b0};
        10'h02: cfg_q = 32'h05800000;
        10'h03: cfg_q = {24'd0, clsz};
        10'h04: cfg_q = {bar0, 16'd0};
        10'h0B: cfg_q = 32'h000710EE;
        10'h0F: cfg_q = {16'd0, 8'h01, iline};
        default: cfg_q = 32'd0;
        endcase
    end

    assign s_arready = (rs == R_AR);
    assign s_rvalid  = (rs == R_R);
    assign s_rdata   = rd;
    assign s_rresp   = 2'b00;
    assign m_araddr  = ra[6:0];
    assign m_arvalid = mar;
    assign m_rready  = (rs == R_F) && !mar;

    always @(posedge clk) begin
        if (!rst_n) begin
            rs <= R_AR;
            mar <= 1'b0;
        end else begin
            case (rs)
            R_AR: if (s_arvalid) begin
                ra <= s_araddr;
                rs <= R_X;
            end
            R_X: begin
                rs <= R_R;
                if (r_cfg) rd <= r_cfg_f0 ? cfg_q : 32'hFFFFFFFF;
                else if (r_hit) begin
                    mar <= 1'b1;
                    rs <= R_F;
                end else rd <= 32'hFFFFFFFF;
            end
            R_F: begin
                if (mar && m_arready) mar <= 1'b0;
                if (m_rready && m_rvalid) begin
                    rd <= m_rdata;
                    rs <= R_R;
                end
            end
            R_R: if (s_rready) rs <= R_AR;
            default: rs <= R_AR;
            endcase
        end
    end
endmodule
