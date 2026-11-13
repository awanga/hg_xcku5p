// SPDX-License-Identifier: MIT
// End-to-end test of the HDMI scan-out in a shrunk mode (64x8 active, 104x16 total): an AXI memory model holds two RGB565 frame buffers, the DUT reads
// them through its register file and fetcher, and a TMDS *receiver model* (clock-channel word alignment, DVI 1.0 decode, control-code recognition)
// reconstructs the video. Expected values come from the memory contents and the mode numbers, not from the DUT: every displayed pixel must equal the
// bit-replicated RGB888 of the memory pixel, run/sync/total counts must equal the mode, a frame buffer base change must take effect at a frame boundary.
`timescale 1ns / 1ps
module tb_hdmi_out #(
    parameter LAT = 6,       // AXI read latency in clk cycles before the first beat of a burst
    parameter GAP = 0,       // idle cycles between beats
    parameter EXPECT_LATE = 0
);
    localparam HA = 64, HF = 8, HS = 16, HB = 16, VA = 8, VF = 2, VS = 2, VB = 4;
    localparam HT = HA + HF + HS + HB, VT = VA + VF + VS + VB;
    localparam BASE_A = 32'h1000, BASE_B = 32'h3000;
    localparam BURST = 8;  // beats per burst: half a line in this mode, so every line needs two bursts

    reg clk = 1'b0, pclk = 1'b0, clk5 = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    always #7.5 pclk = ~pclk;
    always #1.5 clk5 = ~clk5;

    // register port
    reg  [4:0]  s_awaddr = 5'd0, s_araddr = 5'd0;
    reg         s_awvalid = 1'b0, s_wvalid = 1'b0, s_arvalid = 1'b0;
    reg  [31:0] s_wdata = 32'd0;
    wire        s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [1:0]  s_bresp, s_rresp;
    wire [31:0] s_rdata;
    wire [31:0] m_araddr;
    wire [7:0]  m_arlen;
    wire        m_arvalid, m_rready;
    reg         m_arready = 1'b0, m_rvalid = 1'b0;
    reg  [63:0] m_rdata = 64'd0;
    wire        oe;
    wire [3:0]  ser;
    reg         hpd = 1'b0;

    hdmi_out #(.H_ACTIVE(HA), .H_FRONT(HF), .H_SYNC(HS), .H_BACK(HB), .V_ACTIVE(VA), .V_FRONT(VF), .V_SYNC(VS), .V_BACK(VB), .BURST(BURST)) dut (
        .clk(clk), .rst_n(rst_n), .pclk(pclk), .clk5(clk5),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(4'hF),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(1'b1),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rvalid(s_rvalid), .s_rready(1'b1),
        .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arvalid(m_arvalid), .m_arready(m_arready), .m_rdata(m_rdata),
        .m_rresp(2'b00), .m_rvalid(m_rvalid), .m_rready(m_rready), .hpd(hpd), .oe(oe), .ser(ser));

    // ---- frame buffer memory: pixel (x,y) of buffer A / B at BASE + y*128 + x*2; the values are an arbitrary hash of x, y and the buffer
    reg [7:0] mem [0:16383];
    function [15:0] pixval;
        input integer buf_sel, xx, yy;
        begin
            pixval = (xx * 2477 + yy * 9181 + buf_sel * 40503 + (xx ^ (yy << 3)) * 31) & 16'hFFFF;
        end
    endfunction
    integer mi, mx, my;
    initial begin
        for (mi = 0; mi < 16384; mi = mi + 1) mem[mi] = 8'hEE;
        for (my = 0; my < VA; my = my + 1)
            for (mx = 0; mx < HA; mx = mx + 1) begin
                mem[BASE_A + my * 128 + mx * 2] = pixval(0, mx, my) & 8'hFF;
                mem[BASE_A + my * 128 + mx * 2 + 1] = pixval(0, mx, my) >> 8;
                mem[BASE_B + my * 128 + mx * 2] = pixval(1, mx, my) & 8'hFF;
                mem[BASE_B + my * 128 + mx * 2 + 1] = pixval(1, mx, my) >> 8;
            end
    end

    // ---- AXI read slave: a queue of burst addresses, one burst served at a time
    reg [31:0] q_addr [0:7];
    integer q_wr = 0, q_rd = 0, state = 0, wait_cnt = 0, beat = 0, gap_cnt = 0, axi_errors = 0;
    reg [31:0] cur;
    integer ib;
    always @(posedge clk) begin
        m_arready <= 1'b0;
        if (m_arvalid && !m_arready && (q_wr - q_rd) < 8) begin
            m_arready <= 1'b1;
            q_addr[q_wr % 8] <= m_araddr;
            q_wr <= q_wr + 1;
            if (m_araddr[5:0] != 6'd0 || m_arlen != BURST - 1 || (m_araddr[11:0] + 12'd64 < m_araddr[11:0] && m_araddr[11:0] != 12'd0)) axi_errors <= axi_errors + 1;
        end
        case (state)
            0: if (q_wr != q_rd) begin
                state <= 1;
                wait_cnt <= LAT;
                cur <= q_addr[q_rd % 8];
            end
            1: if (wait_cnt == 0) begin
                state <= 2;
                beat <= 0;
                gap_cnt <= 0;
            end else wait_cnt <= wait_cnt - 1;
            2: begin
                if (m_rvalid && m_rready) begin
                    m_rvalid <= 1'b0;
                    beat <= beat + 1;
                    gap_cnt <= GAP;
                    if (beat == BURST - 1) begin
                        state <= 0;
                        q_rd <= q_rd + 1;
                    end
                end else if (!m_rvalid) begin
                    if (gap_cnt == 0) begin
                        for (ib = 0; ib < 8; ib = ib + 1) m_rdata[ib * 8 +: 8] <= mem[cur + beat * 8 + ib];
                        m_rvalid <= 1'b1;
                    end else gap_cnt <= gap_cnt - 1;
                end
            end
            default: state <= 0;
        endcase
    end

    // ---- register access (negedge drive, sample just before posedge)
    reg got;
    task wr;
        input [4:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            s_awaddr = a; s_awvalid = 1'b1; s_wdata = d; s_wvalid = 1'b1;
            got = 1'b0;
            while (!got) begin
                #4;
                got = s_awready && s_wready;
                @(negedge clk);
            end
            s_awvalid = 1'b0; s_wvalid = 1'b0;
            while (!s_bvalid) @(negedge clk);
            @(negedge clk);
        end
    endtask
    reg [31:0] rd_val;
    task rd;
        input [4:0] a;
        begin
            @(negedge clk);
            s_araddr = a; s_arvalid = 1'b1;
            got = 1'b0;
            while (!got) begin
                #4;
                got = s_arready;
                @(negedge clk);
            end
            s_arvalid = 1'b0;
            while (!s_rvalid) @(negedge clk);
            rd_val = s_rdata;
            @(negedge clk);
        end
    endtask

    // ---- TMDS receiver model
    function [7:0] dvi_decode;
        input [9:0] w;
        reg [7:0] y;
        integer j;
        begin
            y = w[9] ? ~w[7:0] : w[7:0];
            dvi_decode[0] = y[0];
            for (j = 1; j < 8; j = j + 1) dvi_decode[j] = w[8] ? (y[j] ^ y[j-1]) : ~(y[j] ^ y[j-1]);
        end
    endfunction
    function [7:0] expand5;
        input [4:0] v;
        begin expand5 = v * 8 + v / 4; end
    endfunction
    function [7:0] expand6;
        input [5:0] v;
        begin expand6 = v * 4 + v / 16; end
    endfunction

    // sample both edges of clk5, shortly after each
    reg [3:0] bit_stream;
    reg       sample_toggle = 1'b0;
    reg [3:0] hist_c = 4'd0;
    integer   pos = -1;       // bit position within the current word, -1 = not aligned
    reg [9:0] sh_b = 10'd0, sh_g = 10'd0, sh_r = 10'd0;
    reg       prev_c = 1'b0;
    // per-pixel decoded stream
    integer px_count = 0, rx_x = 0, rx_line = 0, frame_no = 0, run_len = 0;
    reg     in_data = 1'b0;
    integer hs_low = 0, vs_low = 0, pix_total = 0, frame_started = 0;
    integer errors = 0, checks = 0, frames_ok = 0, data_px = 0;
    reg [1:0] ctl;
    reg [7:0] db, dg, dr;
    reg [15:0] exp565;
    integer sel;           // 0 = A, 1 = B for the current frame, -1 unknown
    integer sel_hist [0:15];
    integer seen_a = 0, seen_b = 0;
    reg [9:0] w_b, w_g, w_r;

    task rx_word_core;
        begin
            w_b = sh_b; w_g = sh_g; w_r = sh_r;
            px_count = px_count + 1;
            pix_total = pix_total + 1;
            if (w_b == 10'b1101010100 || w_b == 10'b0010101011 || w_b == 10'b0101010100 || w_b == 10'b1010101011) begin
                // control period: channels g and r must carry code 00 (1101010100)
                if (w_g !== 10'b1101010100 || w_r !== 10'b1101010100) begin errors = errors + 1; $display("FAIL control g/r %b %b", w_g, w_r); end
                case (w_b)
                    10'b1101010100: ctl = 2'b00;
                    10'b0010101011: ctl = 2'b01;
                    10'b0101010100: ctl = 2'b10;
                    default: ctl = 2'b11;
                endcase
                if (in_data) begin
                    // end of a data run
                    checks = checks + 1;
                    if (run_len != HA) begin errors = errors + 1; $display("FAIL run length %0d", run_len); end
                    in_data = 1'b0;
                    rx_line = rx_line + 1;
                end
                if (ctl[0] == 1'b0) hs_low = hs_low + 1;
                if (ctl[1] == 1'b0) vs_low = vs_low + 1;
                // a falling vsync (first low pixel after high) restarts line counting; frame totals checked when the next one arrives
                if (ctl[1] == 1'b0 && prev_vs_hi) begin
                    if (frame_started) begin
                        checks = checks + 4;
                        if (pix_total != HT * VT) begin errors = errors + 1; $display("FAIL frame %0d pixels %0d want %0d", frame_no, pix_total, HT * VT); end
                        if (hs_low != HS * VT) begin errors = errors + 1; $display("FAIL hsync low %0d want %0d", hs_low, HS * VT); end
                        if (vs_low_prev != VS * HT) begin errors = errors + 1; $display("FAIL vsync low %0d want %0d", vs_low_prev, VS * HT); end
                        if (rx_line != VA) begin errors = errors + 1; $display("FAIL lines %0d want %0d", rx_line, VA); end
                        frames_ok = frames_ok + 1;
                    end
                    frame_started = 1;
                    frame_no = frame_no + 1;
                    pix_total = 0; hs_low = 0; rx_line = 0;
                    vs_low_prev = vs_low;
                    vs_low = 1;
                    sel = -1;
                end
                prev_vs_hi = ctl[1];
                if (ctl[1] == 1'b0) vs_low_prev = vs_low;
            end else begin
                // data period: all three channels decode
                if (!in_data) begin in_data = 1'b1; run_len = 0; end
                db = dvi_decode(w_b); dg = dvi_decode(w_g); dr = dvi_decode(w_r);
                if (frame_started && rx_line < VA && run_len < HA && EXPECT_LATE == 0) begin
                    if (sel == -1) begin
                        if (rx_line == 0 && run_len == 0) begin
                            // choose the buffer whose pixel (0,0) matches
                            if ({dr[7:3], dg[7:2], db[7:3]} == pixval(0, 0, 0)) begin sel = 0; seen_a = seen_a + 1; end
                            else if ({dr[7:3], dg[7:2], db[7:3]} == pixval(1, 0, 0)) begin sel = 1; seen_b = seen_b + 1; end
                        end
                    end
                    if (sel >= 0) begin
                        exp565 = pixval(sel, run_len, rx_line);
                        checks = checks + 1;
                        if (dr !== expand5(exp565[15:11]) || dg !== expand6(exp565[10:5]) || db !== expand5(exp565[4:0])) begin
                            errors = errors + 1;
                            if (errors < 10) $display("FAIL pixel frame %0d (%0d,%0d) buf %0d: got %h %h %h want %h %h %h", frame_no, run_len, rx_line, sel, dr, dg, db,
                                                      expand5(exp565[15:11]), expand6(exp565[10:5]), expand5(exp565[4:0]));
                        end
                        data_px = data_px + 1;
                    end else if (rx_line == 0 && run_len == 0 && frame_no > 1) begin
                        errors = errors + 1; $display("FAIL frame %0d matches neither buffer at (0,0)", frame_no);
                    end
                end
                run_len = run_len + 1;
            end
        end
    endtask
    reg prev_vs_hi = 1'b1;
    integer vs_low_prev = 0;
    // the receiver only evaluates the stream while the DUT's scan-out is enabled (the output before that is not a video signal)
    task rx_word;
        begin
            if (dut.en_p2 !== 1'b1) begin
                frame_started = 0; in_data = 1'b0; prev_vs_hi = 1'b1;
            end else rx_word_core;
        end
    endtask

    // bit sampler: after each clk5 edge take one bit per channel; align on the clock channel (word = 5 zeros then 5 ones, LSB first)
    reg [3:0] s;
    reg [9:0] clk_sh = 10'd0;
    reg       aligned = 1'b0;
    integer   bitcnt = 0;
    task take_bit;
        begin
            s = ser;
            sh_b = {s[0], sh_b[9:1]};
            sh_g = {s[1], sh_g[9:1]};
            sh_r = {s[2], sh_r[9:1]};
            clk_sh = {s[3], clk_sh[9:1]};
            if (!aligned) begin
                // clk_sh (oldest bit in [0]) == 5 zeros then 5 ones means the word that just completed is aligned
                if (clk_sh === 10'b1111100000) begin aligned = 1'b1; bitcnt = 0; rx_word; end
            end else begin
                bitcnt = bitcnt + 1;
                if (bitcnt == 10) begin
                    bitcnt = 0;
                    if (clk_sh !== 10'b1111100000) begin errors = errors + 1; $display("FAIL clock channel lost alignment"); aligned = 1'b0; end
                    else rx_word;
                end
            end
        end
    endtask
    always @(posedge clk5) begin #0.75; take_bit; end
    always @(negedge clk5) begin #0.75; take_bit; end

    // ---- sequence
    integer fr;
    initial begin
        sel = -1;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(negedge clk);
        rd(5'h18);
        checks = checks + 1;
        if (rd_val !== HA * 65536 + VA) begin errors = errors + 1; $display("FAIL MODE %h", rd_val); end
        rd(5'h08); if (rd_val[0] !== 1'b0) begin errors = errors + 1; $display("FAIL hpd should be 0"); end
        hpd = 1'b1;
        repeat (4) @(negedge clk);
        rd(5'h08); if (rd_val[0] !== 1'b1) begin errors = errors + 1; $display("FAIL hpd should be 1"); end
        wr(5'h04, BASE_A);
        wr(5'h00, 32'd3);
        checks = checks + 1;
        if (oe !== 1'b1) begin errors = errors + 1; $display("FAIL oe"); end
        // run 4 frames on buffer A, switch to B in the middle of a frame, run 4 more
        repeat (4 * HT * VT * 15 / 10 + 50) @(negedge clk);
        wr(5'h04, BASE_B);
        repeat (5 * HT * VT * 15 / 10) @(negedge clk);
        rd(5'h0C); checks = checks + 1;
        if (rd_val < 8) begin errors = errors + 1; $display("FAIL frames counter %0d", rd_val); end
        rd(5'h10); checks = checks + 1;
        if (EXPECT_LATE == 0 && rd_val != 0) begin errors = errors + 1; $display("FAIL late lines %0d", rd_val); end
        if (EXPECT_LATE != 0 && rd_val == 0) begin errors = errors + 1; $display("FAIL expected late lines"); end
        rd(5'h14); checks = checks + 1;
        if (EXPECT_LATE == 0 && rd_val < 8 * VA) begin errors = errors + 1; $display("FAIL lines fetched %0d", rd_val); end
        rd(5'h08); checks = checks + 1;
        if (rd_val[3] !== 1'b0) begin errors = errors + 1; $display("FAIL read error flag"); end
        if (EXPECT_LATE == 0) begin
            checks = checks + 3;
            if (frames_ok < 6) begin errors = errors + 1; $display("FAIL only %0d complete frames seen", frames_ok); end
            if (seen_a < 2 || seen_b < 2) begin errors = errors + 1; $display("FAIL frames of A %0d, of B %0d", seen_a, seen_b); end
            if (axi_errors != 0) begin errors = errors + 1; $display("FAIL AXI burst shape errors %0d", axi_errors); end
        end
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d frames=%0d A=%0d B=%0d PASS", checks, errors, frames_ok, seen_a, seen_b);
        else $display("TBRESULT checks=%0d errors=%0d frames=%0d A=%0d B=%0d FAIL", checks, errors, frames_ok, seen_a, seen_b);
        $finish;
    end
    initial begin
        #30000000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
