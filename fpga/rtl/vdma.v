// SPDX-License-Identifier: MIT
// XDMA-compatible DMA subset for the logical PCIe root complex (decision 0008, stage 2): one H2C and one C2H channel with scatter-gather descriptors in
// memory, the register layout of AMD PG195 as far as the AMD example-design test bench exercises it (channel control 0x04, status 0x40/0x44, completed
// descriptor count 0x48, descriptor address 0x4080/0x5080, 32-byte descriptors with the 0xAD4B magic), plus the identifier, interrupt-enable and
// interrupt-request registers a driver reads. Both "host memory" and "card memory" are DDR4 behind the hub DMA port: a descriptor copies bytes from its source
// to its destination, and the CARD side (H2C destination, C2H source) must lie inside the window the firmware opened (win_base/win_size, closed at reset).
// One AXI4 master, 64-bit, one transfer at a time (H2C is served before C2H when both are started).
//   Register map (byte offsets in the 64 KiB block):
//     0x0000 H2C channel, 0x1000 C2H channel: 0x00 identifier 0x1FC0'0006 / 0x1FC1'0006; 0x04 control (bit0 run, bits 1-6 and 9-23 interrupt enables that
//       match the status bits; bit 25/26 stored); 0x08 control W1S; 0x0C control W1C; 0x40 status (bit0 busy = running or queued, latched events below);
//       0x44 status, read clears the latched events; 0x48 completed descriptor count (cleared when a run starts); 0x4C alignments (RO 0x00080820).
//       status bits: 1 descriptor stopped, 2 descriptor completed, 3 alignment mismatch, 4 magic stopped, 5 invalid length, 9 read error (AXI error, or the
//       source outside the window / above 4 GiB), 14 write error (likewise for the destination), 19 descriptor fetch error.
//     0x2000 IRQ block: 0x00 identifier 0x1FC2'0006; 0x04 user interrupt enable (bit 0 = the CPU doorbell), W1S 0x08, W1C 0x0C; 0x10 channel interrupt
//       enable (bit0 H2C, bit1 C2H), W1S 0x14, W1C 0x18; 0x40 user request; 0x44 channel request; 0x48 user pending; 0x4C channel pending.
//     0x3000 config block: identifier 0x1FC3'0006.   0x4000 H2C SGDMA / 0x5000 C2H SGDMA: identifier 0x1FC4'0006 / 0x1FC5'0006, 0x80/0x84 first descriptor
//       address (low/high), 0x88 and 0x8C stored but unused.   0x6000 SGDMA common: identifier 0x1FC6'0006.
//   A run starts on the rising edge of control bit 0: the descriptor at the SGDMA address is fetched, executed, and the chain followed through next_addr
//   until a descriptor with the stop bit (control bit 0) or an error; clearing the run bit stops the chain at the next descriptor boundary. Addresses and
//   lengths must be multiples of 8 and below 4 GiB. The interrupt output is the XDMA legacy interrupt: (user request & enable) or any
//   (channel request & channel enable). Not implemented: streaming, bypass, MSI/MSI-X, poll-mode write-back, the adjacent-descriptor count, performance counters.
module vdma (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] s_awaddr,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,
    input  wire [15:0] s_araddr,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rvalid,
    input  wire        s_rready,
    // AXI4 master toward the hub DMA port (64-bit, INCR, no IDs)
    output wire [31:0] m_awaddr,
    output wire [7:0]  m_awlen,
    output wire        m_awvalid,
    input  wire        m_awready,
    output wire [63:0] m_wdata,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready,
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire        m_arvalid,
    input  wire        m_arready,
    input  wire [63:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready,
    input  wire [31:0] win_base,
    input  wire [31:0] win_size,
    input  wire        user_req,
    output wire        intx
);
    localparam [31:0] EV    = 32'h00FFFE7E;   // latched status bits
    localparam [31:0] CTLM  = 32'h06FFFE7F;   // writable control bits
    localparam [31:0] FLAG  = 32'h0006;       // version field of every identifier

    // ------------------------------------------------------------- register bus
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] addr;
    wire        we, re;
    wire [31:0] wd, rdata;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [3:0]  wstrb_q;   // registers are written whole
    /* verilator lint_on UNUSEDSIGNAL */
    axil_simple #(.AW(16)) u_bus (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .addr(addr), .we(we), .wdata(wd), .wstrb(wstrb_q), .re(re), .rdata(rdata));

    /* verilator lint_on UNUSEDSIGNAL */
    wire [3:0] blk = addr[15:12];
    wire [9:0] off = addr[11:2];

    reg [31:0] ctl0, ctl1, stl0, stl1, cnt0, cnt1, uen, wb0, wb1;
    reg [31:0] da0, da1, dah0, dah1;
    reg [1:0]  cen;
    reg [1:0]  pend;      // started, not yet picked by the engine
    reg [1:0]  run_q;
    reg        ev_do, ev_ch;     // a registered event for channel ev_ch, applied to the latched status
    reg [31:0] ev_bits;

    // engine state
    localparam [3:0] E_IDLE = 4'd0, E_DAR = 4'd1, E_DR = 4'd2, E_CHK = 4'd3, E_RAR = 4'd4, E_RD = 4'd5, E_WAW = 4'd6, E_WW = 4'd7, E_WB = 4'd8, E_NEXT = 4'd9;
    reg [3:0]  st;
    reg        cur;                // channel being served: 0 H2C, 1 C2H
    reg [31:0] dptr, dhi;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [63:0] d0;   // ctrl in the low dword (bits 31:16 magic, 1 completed, 0 stop), length in the high dword
    /* verilator lint_on UNUSEDSIGNAL */
    reg [63:0] d1, d2, d3;
    reg [1:0]  idx;
    reg [4:0]  bidx;
    reg [31:0] src_a, dst_a;
    reg [27:0] rem;
    reg [7:0]  nb;                // bytes of the chunk in flight
    reg [7:0]  nbeats_m1_q;       // its beats minus one, as sent on AW
    reg        rerr;
    reg [63:0] buf_m [0:15];

    // busy stays set until the final event has reached the latched status
    wire busy0 = pend[0] || (st != E_IDLE && !cur) || (ev_do && !ev_ch);
    wire busy1 = pend[1] || (st != E_IDLE && cur) || (ev_do && ev_ch);

    // ------------------------------------------------------------- chunk size: at most 128 bytes, within 4 KiB of both pointers, at most what is left
    wire [12:0] s4k = 13'h1000 - {1'b0, src_a[11:0]};
    wire [12:0] d4k = 13'h1000 - {1'b0, dst_a[11:0]};
    wire [12:0] m1  = (s4k < d4k) ? s4k : d4k;
    wire [12:0] m2  = (m1 < 13'd128) ? m1 : 13'd128;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [12:0] n13 = (rem < {15'd0, m2}) ? rem[12:0] : m2;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [7:0]  nbeats_m1 = n13[10:3] - 8'd1;

    // ------------------------------------------------------------- descriptor checks (E_CHK)
    wire [27:0] dlen   = d0[59:32];
    wire        magic  = (d0[31:16] == 16'hAD4B);
    wire        stop_b = d0[0];
    wire        cmpl_b = d0[1];
    wire        host_src_hi = (d1[63:32] != 32'd0);
    wire        host_dst_hi = (d2[63:32] != 32'd0);
    wire [33:0] w_end = {2'b00, win_base} + {2'b00, win_size};
    wire [33:0] s_end = {2'b00, d1[31:0]} + {6'd0, dlen};
    wire [33:0] t_end = {2'b00, d2[31:0]} + {6'd0, dlen};
    wire        s_win = (d1[31:0] >= win_base) && (s_end <= w_end);
    wire        t_win = (d2[31:0] >= win_base) && (t_end <= w_end);
    wire        src_bad = host_src_hi || (cur ? !s_win : 1'b0);   // C2H source is card memory
    wire        dst_bad = host_dst_hi || (cur ? 1'b0 : !t_win);   // H2C destination is card memory
    wire        misal   = (d1[2:0] != 3'd0) || (d2[2:0] != 3'd0) || (dlen[2:0] != 3'd0);

    // ------------------------------------------------------------- AXI master
    assign m_araddr  = (st == E_DAR) ? dptr : src_a;
    assign m_arlen   = (st == E_DAR) ? 8'd3 : nbeats_m1;
    assign m_arvalid = (st == E_DAR && dhi == 32'd0) || (st == E_RAR);
    assign m_rready  = (st == E_DR) || (st == E_RD);
    assign m_awaddr  = dst_a;
    assign m_awlen   = nbeats_m1_q;
    assign m_awvalid = (st == E_WAW);
    assign m_wdata   = buf_m[bidx[3:0]];
    assign m_wlast   = (bidx[3:0] == nbeats_m1_q[3:0]);
    assign m_wvalid  = (st == E_WW);
    assign m_bready  = (st == E_WB);
    // ------------------------------------------------------------- events
    reg        rc_do, rc_ch;
    always @(posedge clk) begin
        if (!rst_n) begin
            ctl0 <= 32'd0; ctl1 <= 32'd0; stl0 <= 32'd0; stl1 <= 32'd0; cnt0 <= 32'd0; cnt1 <= 32'd0;
            uen <= 32'd0; cen <= 2'd0; pend <= 2'd0; run_q <= 2'd0;
            da0 <= 32'd0; da1 <= 32'd0; dah0 <= 32'd0; dah1 <= 32'd0; wb0 <= 32'd0; wb1 <= 32'd0;
            st <= E_IDLE; cur <= 1'b0; rc_do <= 1'b0; rc_ch <= 1'b0; ev_do <= 1'b0; ev_ch <= 1'b0; ev_bits <= 32'd0;
        end else begin
            rc_do <= 1'b0;
            run_q <= {ctl1[0], ctl0[0]};
            ev_do <= 1'b0;
            // ---- register writes
            if (we) begin
                case (blk)
                4'h0: case (off)
                    10'h01: ctl0 <= wd & CTLM;
                    10'h02: ctl0 <= ctl0 | (wd & CTLM);
                    10'h03: ctl0 <= ctl0 & ~wd;
                    10'h22: wb0 <= wd;
                    default: ;
                    endcase
                4'h1: case (off)
                    10'h01: ctl1 <= wd & CTLM;
                    10'h02: ctl1 <= ctl1 | (wd & CTLM);
                    10'h03: ctl1 <= ctl1 & ~wd;
                    10'h22: wb1 <= wd;
                    default: ;
                    endcase
                4'h2: case (off)
                    10'h01: uen <= wd;
                    10'h02: uen <= uen | wd;
                    10'h03: uen <= uen & ~wd;
                    10'h04: cen <= wd[1:0];
                    10'h05: cen <= cen | wd[1:0];
                    10'h06: cen <= cen & ~wd[1:0];
                    default: ;
                    endcase
                4'h4: case (off)
                    10'h20: da0 <= wd;
                    10'h21: dah0 <= wd;
                    default: ;
                    endcase
                4'h5: case (off)
                    10'h20: da1 <= wd;
                    10'h21: dah1 <= wd;
                    default: ;
                    endcase
                default: ;
                endcase
            end
            // ---- the status read that clears (set wins, see below)
            if (re && (blk == 4'h0 || blk == 4'h1) && off == 10'h11) begin
                rc_do <= 1'b1;
                rc_ch <= blk[0];
            end
            // ---- start requests on the rising edge of the run bit
            if (ctl0[0] && !run_q[0] && !busy0) pend[0] <= 1'b1;
            if (ctl1[0] && !run_q[1] && !busy1) pend[1] <= 1'b1;

            // ---- engine
            case (st)
            E_IDLE: begin
                if (pend[0] || pend[1]) begin
                    cur <= !pend[0];
                    if (pend[0]) begin
                        pend[0] <= 1'b0; dptr <= da0; dhi <= dah0; cnt0 <= 32'd0;
                    end else begin
                        pend[1] <= 1'b0; dptr <= da1; dhi <= dah1; cnt1 <= 32'd0;
                    end
                    st <= E_DAR;
                    rerr <= 1'b0;
                end
            end
            E_DAR: begin
                if (dhi != 32'd0) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00080000; ev_ch <= cur; st <= E_IDLE;
                end else if (m_arready) begin
                    idx <= 2'd0; st <= E_DR;
                end
            end
            E_DR: if (m_rvalid) begin
                case (idx)
                2'd0: d0 <= m_rdata;
                2'd1: d1 <= m_rdata;
                2'd2: d2 <= m_rdata;
                default: d3 <= m_rdata;
                endcase
                if (m_rresp != 2'b00) rerr <= 1'b1;
                idx <= idx + 2'd1;
                if (m_rlast) st <= E_CHK;
            end
            E_CHK: begin
                st <= E_RAR;
                if (rerr) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00080000; ev_ch <= cur; st <= E_IDLE;
                end else if (!magic) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00000010; ev_ch <= cur; st <= E_IDLE;
                end else if (dlen == 28'd0) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00000020; ev_ch <= cur; st <= E_IDLE;
                end else if (misal) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00000008; ev_ch <= cur; st <= E_IDLE;
                end else if (src_bad) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00000200; ev_ch <= cur; st <= E_IDLE;
                end else if (dst_bad) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00004000; ev_ch <= cur; st <= E_IDLE;
                end else begin
                    src_a <= d1[31:0];
                    dst_a <= d2[31:0];
                    rem <= dlen;
                end
            end
            E_RAR: if (m_arready) begin
                nb <= n13[7:0];
                nbeats_m1_q <= nbeats_m1;
                bidx <= 5'd0;
                st <= E_RD;
                rerr <= 1'b0;
            end
            E_RD: if (m_rvalid) begin
                buf_m[bidx[3:0]] <= m_rdata;
                bidx <= bidx + 5'd1;
                if (m_rresp != 2'b00) rerr <= 1'b1;
                if (m_rlast) begin
                    if (rerr || m_rresp != 2'b00) begin
                        ev_do <= 1'b1; ev_bits <= 32'h00000200; ev_ch <= cur; st <= E_IDLE;
                    end else st <= E_WAW;
                end
            end
            E_WAW: if (m_awready) begin
                bidx <= 5'd0;
                st <= E_WW;
            end
            E_WW: if (m_wready) begin
                bidx <= bidx + 5'd1;
                if (m_wlast) st <= E_WB;
            end
            E_WB: if (m_bvalid) begin
                if (m_bresp != 2'b00) begin
                    ev_do <= 1'b1; ev_bits <= 32'h00004000; ev_ch <= cur; st <= E_IDLE;
                end else begin
                    src_a <= src_a + {24'd0, nb};
                    dst_a <= dst_a + {24'd0, nb};
                    rem <= rem - {20'd0, nb};
                    st <= (rem == {20'd0, nb}) ? E_NEXT : E_RAR;
                end
            end
            E_NEXT: begin
                if (cur) cnt1 <= cnt1 + 32'd1; else cnt0 <= cnt0 + 32'd1;
                ev_do <= 1'b1;
                ev_ch <= cur;
                if (stop_b || !(cur ? ctl1[0] : ctl0[0]) || d3 == 64'd0) begin
                    ev_bits <= (cmpl_b ? 32'h00000006 : 32'h00000002);
                    st <= E_IDLE;
                end else begin
                    ev_bits <= (cmpl_b ? 32'h00000004 : 32'h00000000);
                    dptr <= d3[31:0];
                    dhi <= d3[63:32];
                    rerr <= 1'b0;
                    st <= E_DAR;
                end
            end
            default: st <= E_IDLE;
            endcase

            // ---- latched events: set wins over the clear of a read
            stl0 <= (stl0 & ~((rc_do && !rc_ch) ? EV : 32'd0)) | ((ev_do && !ev_ch) ? ev_bits : 32'd0);
            stl1 <= (stl1 & ~((rc_do && rc_ch) ? EV : 32'd0)) | ((ev_do && ev_ch) ? ev_bits : 32'd0);
        end
    end

    // ------------------------------------------------------------- register reads and the interrupt
    wire [31:0] st0 = (stl0 & EV) | {31'd0, busy0};
    wire [31:0] st1 = (stl1 & EV) | {31'd0, busy1};
    wire [1:0]  creq = {|(stl1 & ctl1 & EV), |(stl0 & ctl0 & EV)};
    reg [31:0] rd;
    always @* begin
        rd = 32'd0;
        case (blk)
        4'h0, 4'h1: case (off)
            10'h00: rd = {12'h1FC, 3'd0, blk[0], 8'd0, FLAG[7:0]};
            10'h01: rd = blk[0] ? ctl1 : ctl0;
            10'h10: rd = blk[0] ? st1 : st0;
            10'h11: rd = blk[0] ? st1 : st0;
            10'h12: rd = blk[0] ? cnt1 : cnt0;
            10'h13: rd = 32'h00080820;
            10'h22: rd = blk[0] ? wb1 : wb0;
            default: rd = 32'd0;
            endcase
        4'h2: case (off)
            10'h00: rd = {12'h1FC, 4'd2, 8'd0, FLAG[7:0]};
            10'h01: rd = uen;
            10'h04: rd = {30'd0, cen};
            10'h10: rd = {31'd0, user_req};
            10'h11: rd = {30'd0, creq};
            10'h12: rd = {31'd0, user_req & uen[0]};
            10'h13: rd = {30'd0, creq & cen};
            default: rd = 32'd0;
            endcase
        4'h3: rd = (off == 10'h00) ? {12'h1FC, 4'd3, 8'd0, FLAG[7:0]} : 32'd0;
        4'h4, 4'h5: case (off)
            10'h00: rd = {12'h1FC, blk[3:0], 8'd0, FLAG[7:0]};
            10'h20: rd = blk[0] ? da1 : da0;
            10'h21: rd = blk[0] ? dah1 : dah0;
            default: rd = 32'd0;
            endcase
        4'h6: rd = (off == 10'h00) ? {12'h1FC, 4'd6, 8'd0, FLAG[7:0]} : 32'd0;
        default: rd = 32'd0;
        endcase
    end
    assign rdata = rd;
    assign intx = (user_req & uen[0]) | (|(creq & cen));
endmodule
