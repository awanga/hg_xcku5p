// SPDX-License-Identifier: MIT
// spi_sifive against an independent SPI slave model written from the SPI mode definition (sample edge = rising when CPOL == CPHA).
// Sweeps CPOL/CPHA, bit order and clock divider; checks transmitted bytes, received bytes, chip-select framing and FIFO flags.
`timescale 1ns / 1ps
module tb_spi_sifive;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg        we = 1'b0, re = 1'b0;
    reg [6:0]  addr = 7'd0;
    reg [31:0] wdata = 32'd0;
    wire [31:0] rdata;
    wire irq, sck, mosi, cs_n;
    reg  miso;

    spi_sifive dut (.clk(clk), .rst_n(rst_n), .we(we), .addr(addr), .wdata(wdata), .re(re), .rdata(rdata), .irq(irq),
                    .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n));

    integer errors = 0;
    integer checks = 0;
    task check(input cond, input [255:0] what);
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s (t=%0t)", what, $time); end
        end
    endtask

    task wr(input [6:0] a, input [31:0] d);
        begin
            @(negedge clk); we = 1'b1; addr = a; wdata = d;
            @(negedge clk); we = 1'b0;
        end
    endtask
    task rd(input [6:0] a, output [31:0] d);
        begin
            @(negedge clk); re = 1'b1; addr = a;
            @(negedge clk); re = 1'b0;
            @(negedge clk); d = rdata;
        end
    endtask

    // slave model
    reg        s_pha = 1'b0, s_pol = 1'b0, s_lsb = 1'b0;
    reg [7:0]  reply [0:7];
    reg [7:0]  got [0:7];
    integer    byte_n = 0, edge_n = 0, cs_frames = 0;
    reg [7:0]  s_rx;
    reg [7:0]  cur_reply;
    reg        cs_prev = 1'b1;
    integer    kk;
    function bit_of(input [7:0] v, input integer k);
        begin bit_of = s_lsb ? v[k] : v[7 - k]; end
    endfunction

    always @(negedge cs_n) begin
        edge_n = 0;
        cs_frames = cs_frames + 1;
        cur_reply = reply[byte_n];
        if (!s_pha) miso = bit_of(cur_reply, 0);
    end
    always @(sck) begin
        if (!cs_n && rst_n) begin
            edge_n = edge_n + 1;
            if (!s_pha) begin
                if (edge_n % 2 == 1) s_rx[s_lsb ? (edge_n - 1) / 2 : 7 - (edge_n - 1) / 2] = mosi;
                else if (edge_n < 16) miso = bit_of(cur_reply, edge_n / 2);
            end else begin
                if (edge_n % 2 == 1) miso = bit_of(cur_reply, (edge_n - 1) / 2);
                else s_rx[s_lsb ? (edge_n / 2) - 1 : 7 - ((edge_n / 2) - 1)] = mosi;
            end
            if (edge_n == 16) begin
                got[byte_n] = s_rx;
                byte_n = byte_n + 1;
                edge_n = 0;
                cur_reply = reply[byte_n];
                if (!s_pha) miso = bit_of(cur_reply, 0);
            end
        end
    end

    reg [31:0] v;
    integer pol, pha, lsb, div, i, nb;
    reg [7:0] txb [0:7];
    initial begin
        miso = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        rd(7'h00, v); check(v == 32'd3, "sckdiv reset");
        rd(7'h14, v); check(v == 32'd1, "csdef reset");
        check(cs_n === 1'b1, "CS idle after reset");

        for (pol = 0; pol < 2; pol = pol + 1)
          for (pha = 0; pha < 2; pha = pha + 1)
            for (lsb = 0; lsb < 2; lsb = lsb + 1)
              for (div = 0; div < 4; div = div + 3) begin
                s_pol = pol; s_pha = pha; s_lsb = lsb;
                byte_n = 0; cs_frames = 0;
                nb = 3;
                for (i = 0; i < nb; i = i + 1) begin
                    txb[i] = 8'h96 + 8'd37 * i + 8'd16 * pol + 8'd5 * pha;
                    reply[i] = 8'hA5 ^ (8'd91 * i) ^ 8'd3 * lsb;
                end
                wr(7'h00, div);
                wr(7'h04, {30'd0, pol[0], pha[0]});
                wr(7'h40, {12'd0, 4'd8, 12'd0, 1'b0, lsb[0], 2'd0});
                wr(7'h18, 32'd0); // AUTO
                for (i = 0; i < nb; i = i + 1) wr(7'h48, {24'd0, txb[i]});
                // CS must be low while frames are queued, high when done
                repeat (20) @(negedge clk);
                check(cs_n === 1'b0, "CS active during burst");
                wait (byte_n == nb);
                repeat (40) @(negedge clk);
                check(cs_n === 1'b1, "CS released after burst");
                check(cs_frames == 1, "one CS assertion for the burst");
                check(sck === pol[0], "SCK idle level");
                for (i = 0; i < nb; i = i + 1) begin
                    check(got[i] == txb[i], "MOSI byte seen by slave");
                    rd(7'h4C, v);
                    check(v == {24'd0, reply[i]}, "MISO byte read from rxdata");
                end
                rd(7'h4C, v); check(v[31] == 1'b1, "rxdata empty flag");
              end

        // HOLD keeps CS active with an empty FIFO; OFF keeps it idle while shifting
        s_pol = 0; s_pha = 0; s_lsb = 0; byte_n = 0; reply[0] = 8'h00;
        wr(7'h00, 32'd1); wr(7'h04, 32'd0); wr(7'h40, {12'd0, 4'd8, 12'd0, 4'd0});
        wr(7'h18, 32'd2);
        repeat (6) @(negedge clk);
        check(cs_n === 1'b0, "HOLD asserts CS");
        wr(7'h18, 32'd0);
        repeat (6) @(negedge clk);
        check(cs_n === 1'b1, "AUTO releases CS when idle");

        // fmt.dir rewritten while a transmit-only frame is still shifting (spi-sifive does this when a tx transfer
        // is followed by an rx transfer): the frame in flight must not leave a byte in the RX FIFO
        s_pol = 0; s_pha = 0; s_lsb = 0; byte_n = 0; reply[0] = 8'h00;
        wr(7'h18, 32'd0); wr(7'h00, 32'd8); wr(7'h04, 32'd0);
        wr(7'h40, {12'd0, 4'd8, 12'd0, 4'b1000});
        wr(7'h48, 32'h0000_005A);
        repeat (20) @(negedge clk);
        wr(7'h40, {12'd0, 4'd8, 12'd0, 4'd0});
        wait (byte_n == 1);
        repeat (40) @(negedge clk);
        rd(7'h4C, v); check(v[31] == 1'b1, "tx-only frame leaves RX FIFO empty after fmt.dir change");
        check(got[0] == 8'h5A, "tx-only frame data intact");

        // TX FIFO full flag and watermark interrupts
        wr(7'h18, 32'd3); // OFF: frames still shift but CS stays idle
        wr(7'h00, 32'd255);
        wr(7'h50, 32'd4); wr(7'h70, 32'd1);
        rd(7'h74, v); check(v[0] == 1'b1 && irq === 1'b1, "txwm set when FIFO below mark");
        for (i = 0; i < 9; i = i + 1) wr(7'h48, 32'h0000_0055);
        rd(7'h48, v); check(v[31] == 1'b1, "TX FIFO full flag");
        rd(7'h74, v); check(v[0] == 1'b0 && irq === 1'b0, "txwm clear above mark");

        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
    initial begin
        #200000000;
        $display("TBRESULT checks=%0d errors=%0d FAIL (watchdog)", checks, errors + 1);
        $finish;
    end
endmodule
