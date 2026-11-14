// SPDX-License-Identifier: MIT
// SPI master with the register layout of the SiFive FU540 SPI controller, as driven by the mainline Linux spi-sifive driver
// ("sifive,spi0") and by fw/boot. Subset: single-line protocol, 8-bit frames, one chip select, no flash-mode (fctrl) registers.
//
// Register offsets (byte addresses, 32-bit accesses):
//   0x00 sckdiv   [11:0]  f_sck = f_clk / (2 * (div + 1)); reset 3
//   0x04 sckmode  [0] phase (CPHA)  [1] polarity (CPOL)
//   0x10 csid     chip select id (one CS: stored, ignored)
//   0x14 csdef    [0] CS idle level (reset 1: CS is active low)
//   0x18 csmode   0 AUTO (CS active while frames are queued or shifting), 2 HOLD (CS active), 3 OFF (CS idle)
//   0x28 delay0, 0x2C delay1  stored, not implemented (zero delays)
//   0x40 fmt      [2] 1 = LSB first   [3] 1 = transmit only (received frames dropped)   [19:16] frame length (only 8 supported)
//   0x48 txdata   write [7:0] queues a frame; read bit 31 = TX FIFO full
//   0x4C rxdata   read pops: bit 31 = FIFO was empty, [7:0] data
//   0x50 txmark [2:0], 0x54 rxmark [2:0]
//   0x70 ie [1:0] (bit 0 txwm, bit 1 rxwm)    0x74 ip (read only): txwm = tx count < txmark, rxwm = rx count > rxmark
// Contract: the local bus is the axil_simple word bus: we/re pulse one cycle, rdata valid one cycle after re.
module spi_sifive #(
    parameter DEPTH_LOG2 = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [6:0]  addr,      // byte address [6:0]
    input  wire [31:0] wdata,
    input  wire        re,
    output reg  [31:0] rdata,
    output wire        irq,
    output reg         sck,
    output wire        mosi,
    input  wire        miso,
    output wire        cs_n
);
    localparam DEPTH = 1 << DEPTH_LOG2;

    reg [11:0] sckdiv;
    reg        pha, pol;
    reg        csdef;
    reg [1:0]  csmode;
    reg [31:0] delay0, delay1;
    reg        lsb_first, tx_only;
    reg        frame_tx_only; // fmt.dir as of the frame start: the driver rewrites fmt while the last frame is still shifting
    reg [3:0]  frame_len;
    reg [2:0]  txmark, rxmark;
    reg [1:0]  ie;
    reg [7:0]  txf [0:DEPTH-1];
    reg [7:0]  rxf [0:DEPTH-1];
    reg [DEPTH_LOG2:0] tx_wr, tx_rd, rx_wr, rx_rd;

    wire [DEPTH_LOG2:0] tx_cnt = tx_wr - tx_rd;
    wire [DEPTH_LOG2:0] rx_cnt = rx_wr - rx_rd;
    wire tx_full  = (tx_cnt == DEPTH);
    wire rx_empty = (rx_cnt == 0);
    wire txwm = (tx_cnt < {1'b0, txmark});
    wire rxwm = (rx_cnt > {1'b0, rxmark});
    assign irq = (ie[0] & txwm) | (ie[1] & rxwm);

    // shifter
    reg        busy;
    reg [7:0]  shreg;
    reg [7:0]  rxreg;
    reg [3:0]  bitcnt;
    reg [12:0] divcnt;
    reg        half;          // 0: leading edge pending, 1: trailing edge pending
    reg        cs_active;

    wire [7:0] tx_head = txf[tx_rd[DEPTH_LOG2-1:0]];
    wire       cs_want = (csmode == 2'd2) || ((csmode == 2'd0) && (tx_cnt != 0));
    assign cs_n = cs_active ? ~csdef : csdef;
    assign mosi = lsb_first ? shreg[0] : shreg[7];

    wire tick = (divcnt == {1'b0, sckdiv});

    always @(posedge clk) begin
        if (!rst_n) begin
            sckdiv <= 12'd3; pha <= 1'b0; pol <= 1'b0; csdef <= 1'b1; csmode <= 2'd0;
            delay0 <= 32'h0001_0001; delay1 <= 32'h0000_0001;
            lsb_first <= 1'b0; tx_only <= 1'b0; frame_tx_only <= 1'b0; frame_len <= 4'd8;
            txmark <= 3'd1; rxmark <= 3'd0; ie <= 2'd0;
            tx_wr <= 0; tx_rd <= 0; rx_wr <= 0; rx_rd <= 0;
            busy <= 1'b0; sck <= 1'b0; cs_active <= 1'b0; divcnt <= 13'd0; half <= 1'b0;
            shreg <= 8'd0; rxreg <= 8'd0; bitcnt <= 4'd0;
        end else begin
            if (!busy) sck <= pol;
            // register writes
            if (we) begin
                case (addr)
                7'h00: sckdiv <= wdata[11:0];
                7'h04: begin pha <= wdata[0]; pol <= wdata[1]; end
                7'h14: csdef <= wdata[0];
                7'h18: csmode <= wdata[1:0];
                7'h28: delay0 <= wdata;
                7'h2C: delay1 <= wdata;
                7'h40: begin lsb_first <= wdata[2]; tx_only <= wdata[3]; frame_len <= wdata[19:16]; end
                7'h48: if (!tx_full) begin txf[tx_wr[DEPTH_LOG2-1:0]] <= wdata[7:0]; tx_wr <= tx_wr + 1'b1; end
                7'h50: txmark <= wdata[2:0];
                7'h54: rxmark <= wdata[2:0];
                7'h70: ie <= wdata[1:0];
                default: ;
                endcase
            end
            // register reads
            if (re) begin
                case (addr)
                7'h00: rdata <= {20'd0, sckdiv};
                7'h04: rdata <= {30'd0, pol, pha};
                7'h14: rdata <= {31'd0, csdef};
                7'h18: rdata <= {30'd0, csmode};
                7'h28: rdata <= delay0;
                7'h2C: rdata <= delay1;
                7'h40: rdata <= {12'd0, frame_len, 12'd0, tx_only, lsb_first, 2'd0};
                7'h48: rdata <= {tx_full, 31'd0};
                7'h4C: begin
                    rdata <= rx_empty ? 32'h8000_0000 : {24'd0, rxf[rx_rd[DEPTH_LOG2-1:0]]};
                    if (!rx_empty) rx_rd <= rx_rd + 1'b1;
                end
                7'h50: rdata <= {29'd0, txmark};
                7'h54: rdata <= {29'd0, rxmark};
                7'h70: rdata <= {30'd0, ie};
                7'h74: rdata <= {30'd0, rxwm, txwm};
                default: rdata <= 32'd0;
                endcase
            end
            // chip select follows the mode; it only changes between frames
            if (!busy) cs_active <= cs_want;
            // shifter
            if (!busy) begin
                divcnt <= 13'd0;
                half <= 1'b0;
                if (tx_cnt != 0) begin
                    busy <= 1'b1;
                    cs_active <= (csmode != 2'd3);
                    frame_tx_only <= tx_only;
                    shreg <= tx_head;
                    tx_rd <= tx_rd + 1'b1;
                    bitcnt <= 4'd0;
                    // CPHA=1: data changes on the leading edge, so the first leading edge only toggles SCK
                end
            end else if (tick) begin
                divcnt <= 13'd0;
                sck <= ~sck;
                half <= ~half;
                if (!half) begin
                    // leading edge: sample here when CPHA=0, otherwise shift out the next bit
                    if (!pha) rxreg <= lsb_first ? {miso, rxreg[7:1]} : {rxreg[6:0], miso};
                    else if (bitcnt != 4'd0) shreg <= lsb_first ? {1'b0, shreg[7:1]} : {shreg[6:0], 1'b0};
                end else begin
                    // trailing edge: sample when CPHA=1, otherwise shift out the next bit
                    if (pha) rxreg <= lsb_first ? {miso, rxreg[7:1]} : {rxreg[6:0], miso};
                    else shreg <= lsb_first ? {1'b0, shreg[7:1]} : {shreg[6:0], 1'b0};
                    bitcnt <= bitcnt + 1'b1;
                    if (bitcnt == 4'd7) begin
                        busy <= 1'b0;
                        if (!frame_tx_only && rx_cnt != DEPTH) begin
                            rxf[rx_wr[DEPTH_LOG2-1:0]] <= pha ? (lsb_first ? {miso, rxreg[7:1]} : {rxreg[6:0], miso}) : rxreg;
                            rx_wr <= rx_wr + 1'b1;
                        end
                    end
                end
            end else
                divcnt <= divcnt + 1'b1;
        end
    end
endmodule
