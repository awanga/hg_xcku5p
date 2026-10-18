// SPDX-License-Identifier: MIT
// Unit testbench for axi_memtest with a behavioural AXI4 slave.
// FAULT selects a slave defect the DUT must detect (FAULT=0 is the defect-free case):
//   1 flip bit 255 of beat 5 on write      -> err_cnt > 0
//   2 address alias (memory half the size) -> err_cnt > 0
//   3 stop answering reads after pass 1    -> timeout
//   4 SLVERR on write burst 3              -> err_cnt > 0
//   5 rlast one beat early                 -> err_cnt > 0
//   6 SLVERR read response on beat 9       -> err_cnt > 0 (data stays correct)
// Expected pattern words are hard-coded from an independent Python model (see tests/rtl/pattern_model.py).
`timescale 1ns / 1ps
module tb_axi_memtest;
    parameter FAULT = 0;
    parameter STALL = 1;
    parameter NBURSTS = 8;
    localparam MEMBEATS = NBURSTS * 16;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b0;
    always #2.5 clk = ~clk;

    wire [29:0] awaddr, araddr, first_err_addr;
    wire awvalid, wvalid, wlast, arvalid, bready, rready, timeout, busy;
    reg awready, wready, arready, bvalid, rvalid, rlast;
    reg [1:0] bresp, rresp;
    wire [255:0] wdata;
    reg [255:0] rdata;
    wire [31:0] pass_cnt, err_cnt, wr_cycles, rd_cycles;

    axi_memtest #(.NBURSTS(NBURSTS), .TIMEOUT_BITS(12)) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .pass_cnt(pass_cnt), .err_cnt(err_cnt), .wr_cycles(wr_cycles), .rd_cycles(rd_cycles),
        .first_err_addr(first_err_addr), .timeout(timeout), .busy(busy));

    reg [255:0] mem [0:MEMBEATS-1];
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    wire rnd0 = (STALL == 0) ? 1'b1 : lfsr[0];
    wire rnd1 = (STALL == 0) ? 1'b1 : lfsr[5];
    wire rnd2 = (STALL == 0) ? 1'b1 : lfsr[9];

    // write path
    reg aw_got = 1'b0;
    reg [29:0] w_addr = 30'd0;
    reg [3:0] w_beat = 4'd0;
    reg [3:0] b_delay = 4'd0;
    reg b_wait = 1'b0;
    integer wburst = 0;
    integer widx;
    reg stuck = 1'b0;

    always @(*) begin
        awready = rnd0 && !aw_got && !b_wait && !bvalid;
        wready = rnd1 && aw_got;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            aw_got <= 1'b0;
            w_beat <= 4'd0;
            b_wait <= 1'b0;
            bvalid <= 1'b0;
            bresp <= 2'b00;
            wburst = 0;
        end else begin
            if (awvalid && awready) begin
                aw_got <= 1'b1;
                w_addr <= awaddr;
                w_beat <= 4'd0;
            end
            if (wvalid && wready) begin
                widx = (w_addr >> 5) + w_beat;
                if (FAULT == 2)
                    widx = widx % (MEMBEATS / 2);
                mem[widx] <= (FAULT == 1 && widx == 5) ? (wdata ^ (256'd1 << 255)) : wdata;
                w_beat <= w_beat + 1'b1;
                if (wlast) begin
                    aw_got <= 1'b0;
                    b_wait <= 1'b1;
                    b_delay <= lfsr[3:0];
                end
            end
            if (b_wait) begin
                if (b_delay == 0) begin
                    b_wait <= 1'b0;
                    bvalid <= 1'b1;
                    bresp <= (FAULT == 4 && wburst == 3) ? 2'b10 : 2'b00;
                end else
                    b_delay <= b_delay - 1'b1;
            end
            if (bvalid && bready) begin
                bvalid <= 1'b0;
                wburst = wburst + 1;
            end
        end
    end

    // read path
    reg ar_got = 1'b0;
    reg [29:0] r_addr = 30'd0;
    reg [3:0] r_beat = 4'd0;
    integer ridx;
    always @(*) begin
        arready = rnd2 && !ar_got && !stuck;
        ridx = (r_addr >> 5) + r_beat;
        if (FAULT == 2)
            ridx = ridx % (MEMBEATS / 2);
        rdata = mem[ridx];
        rlast = (FAULT == 5) ? (r_beat == 4'd14) : (r_beat == 4'd15);
        rvalid = ar_got && rnd0;
        rresp = (FAULT == 6 && ridx == 9) ? 2'b10 : 2'b00;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_got <= 1'b0;
            r_beat <= 4'd0;
            stuck <= 1'b0;
        end else begin
            if (FAULT == 3 && pass_cnt >= 1)
                stuck <= 1'b1;
            if (arvalid && arready) begin
                ar_got <= 1'b1;
                r_addr <= araddr;
                r_beat <= 4'd0;
            end
            if (rvalid && rready) begin
                r_beat <= r_beat + 1'b1;
                if (r_beat == 4'd15 || (FAULT == 5 && r_beat == 4'd14)) begin
                    ar_got <= 1'b0;
                    r_beat <= 4'd0;
                end
            end
        end
    end

    // independent expectations (Python model): word w of global beat b in pass p
    integer checks = 0;
    integer errors = 0;
    reg [3:0] vec_done = 4'd0;
    task expect32;
        input [255:0] actual;
        input integer lane;
        input [31:0] want;
        begin
            checks = checks + 1;
            if (actual[32*lane +: 32] !== want) begin
                errors = errors + 1;
                $display("VECTOR MISMATCH lane %0d got %h want %h", lane, actual[32*lane +: 32], want);
            end
        end
    endtask
    always @(posedge clk) begin
        if (FAULT == 0 && dut.state == 2'd2 && dut.arvalid) begin
            if (pass_cnt == 0 && !vec_done[0]) begin
                vec_done[0] <= 1'b1;
                expect32(mem[0], 0, 32'h333488ac);
                expect32(mem[0], 7, 32'h3311a985);
                expect32(mem[1], 0, 32'h331589a4);
                expect32(mem[15], 3, 32'h32cf2796);
            end
            if (pass_cnt == 1 && !vec_done[1]) begin
                vec_done[1] <= 1'b1;
                expect32(mem[0], 0, 32'he6e767c4);
                expect32(mem[100], 5, 32'hea1fe671);
            end
            if (pass_cnt == 2 && !vec_done[2]) begin
                vec_done[2] <= 1'b1;
                expect32(mem[100], 5, 32'h5b02d198);
            end
        end
    end

    // monitor: write data must be stable while wvalid && !wready; AXI size/len fixed by the DUT contract
    reg [255:0] wdata_q;
    reg wv_q, wr_q;
    always @(posedge clk) begin
        wdata_q <= wdata;
        wv_q <= wvalid;
        wr_q <= wready;
        if (rst_n && wv_q && !wr_q && wvalid && wdata !== wdata_q) begin
            errors = errors + 1;
            $display("PROTOCOL: wdata changed while stalled");
        end
    end

    integer i;
    integer ok;
    initial begin
        for (i = 0; i < MEMBEATS; i = i + 1)
            mem[i] = 256'd0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        enable = 1'b1;
        i = 0;
        while (i < 200000 && pass_cnt < 4 && !timeout) begin
            @(posedge clk);
            i = i + 1;
        end
        ok = 0;
        case (FAULT)
        0: ok = (pass_cnt >= 4) && (err_cnt == 0) && !timeout && (errors == 0) && (checks == 7)
                && (wr_cycles > 0) && (rd_cycles > 0);
        1, 2, 4, 5, 6: ok = (err_cnt > 0) && !timeout && (errors == 0);
        3: ok = timeout;
        default: ok = 0;
        endcase
        $display("TBRESULT fault=%0d pass=%0d err=%0d timeout=%0d vec_checks=%0d vec_errors=%0d wr=%0d rd=%0d first=%h %s",
                 FAULT, pass_cnt, err_cnt, timeout, checks, errors, wr_cycles, rd_cycles, first_err_addr,
                 ok ? "PASS" : "FAIL");
        $finish;
    end
endmodule
