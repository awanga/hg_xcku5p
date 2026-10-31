// SPDX-License-Identifier: MIT
// System test of the generated LiteEth GMII core (build/liteeth/gateware/liteeth_core.v) through its AXI-Lite port:
// transmit a frame (buffer fill, slot/length/start) and compare the GMII output with preamble + payload + CRC-32;
// receive a good frame (interrupt, slot, length, buffer contents) and a bad-CRC frame (counter, no event).
// The CRC-32 and frame layout are written here from IEEE 802.3, not taken from the core.
`timescale 1ns / 1ps
module tb_liteeth;
    reg clk = 1'b0, rxclk = 1'b0;
    always #5 clk = ~clk;          // 100 MHz sys
    always #4 rxclk = ~rxclk;      // 125 MHz recovered clock (also the TX clock of this PHY core)
    reg rst = 1'b1;

    reg  [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg  [3:0]  wstrb = 4'hF;
    reg         awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [31:0] rdata;
    wire [1:0]  bresp, rresp;
    wire        irq;
    reg  [7:0]  rx_data = 0;
    reg         rx_dv = 0;
    wire [7:0]  tx_data;
    wire        tx_en, tx_er, gtx, rst_n;

    liteeth_core dut (
        .sys_clock(clk), .sys_reset(rst),
        .bus_awaddr(awaddr), .bus_awprot(3'd0), .bus_awvalid(awvalid), .bus_awready(awready),
        .bus_wdata(wdata), .bus_wstrb(wstrb), .bus_wvalid(wvalid), .bus_wready(wready),
        .bus_bresp(bresp), .bus_bvalid(bvalid), .bus_bready(bready),
        .bus_araddr(araddr), .bus_arprot(3'd0), .bus_arvalid(arvalid), .bus_arready(arready),
        .bus_rdata(rdata), .bus_rresp(rresp), .bus_rvalid(rvalid), .bus_rready(rready),
        .interrupt(irq),
        .gmii_clocks_rx(rxclk), .gmii_clocks_tx(1'b0), .gmii_clocks_gtx(gtx),
        .gmii_rst_n(rst_n), .gmii_tx_data(tx_data), .gmii_tx_en(tx_en), .gmii_tx_er(tx_er),
        .gmii_rx_data(rx_data), .gmii_rx_dv(rx_dv), .gmii_rx_er(1'b0),
        .gmii_col(1'b0), .gmii_crs(1'b0), .gmii_int_n(1'b1), .gmii_mdc(), .gmii_mdio());

    localparam CSR = 32'hF8021000, RXBUF = 32'hF8030000, TXBUF = 32'hF8031000;
    localparam W_SLOT = 0, W_LEN = 4, W_ERR = 8, W_PEND = 32'h10, W_EN = 32'h14;
    localparam R_START = 32'h18, R_READY = 32'h1C, R_SLOT = 32'h24, R_LEN = 32'h28, R_PEND = 32'h30, R_EN = 32'h34, CRC_ERR = 32'h40;

    integer errors = 0, checks = 0;
    task check(input cond, input [255:0] what);
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s (t=%0t)", what, $time); end
        end
    endtask

    task axi_wr(input [31:0] a, input [31:0] d);
        integer t;
        begin
            @(negedge clk); awaddr = a; wdata = d; awvalid = 1; wvalid = 1; bready = 1;
            t = 0;
            while (!(awvalid == 0 && wvalid == 0) && t < 2000) begin
                @(posedge clk);
                if (awready) awvalid = 0;
                if (wready) wvalid = 0;
                t = t + 1;
            end
            t = 0;
            while (!bvalid && t < 2000) begin @(posedge clk); t = t + 1; end
            check(bvalid && bresp == 2'b00, "write response OKAY");
            @(negedge clk); bready = 0; awvalid = 0; wvalid = 0;
        end
    endtask

    // AW and W presented at different times, as the clock converter and crossbar do: AW first (ad = 0, wd > 0) or W first.
    task axi_wr_skew(input [31:0] a, input [31:0] d, input integer ad, input integer wd);
        integer t, n;
        reg aw_done, w_done;
        begin
            @(negedge clk); bready = 1; aw_done = 0; w_done = 0; t = 0;
            while (!(aw_done && w_done) && t < 2000) begin
                if (!aw_done && t == ad) begin awaddr = a; awvalid = 1; end
                if (!w_done && t == wd) begin wdata = d; wvalid = 1; end
                @(posedge clk);
                if (awvalid && awready) begin aw_done = 1; end
                if (wvalid && wready) begin w_done = 1; end
                @(negedge clk);
                if (aw_done) awvalid = 0;
                if (w_done) wvalid = 0;
                t = t + 1;
            end
            t = 0;
            while (!bvalid && t < 2000) begin @(posedge clk); t = t + 1; end
            check(bvalid && bresp == 2'b00, "skewed write response OKAY");
            @(negedge clk); bready = 0; awvalid = 0; wvalid = 0;
        end
    endtask

    task axi_rd(input [31:0] a, output [31:0] d);
        integer t;
        begin
            @(negedge clk); araddr = a; arvalid = 1; rready = 1;
            t = 0;
            while (arvalid && t < 2000) begin @(posedge clk); if (arready) arvalid = 0; t = t + 1; end
            t = 0;
            while (!rvalid && t < 2000) begin @(posedge clk); t = t + 1; end
            check(rvalid && rresp == 2'b00, "read response OKAY");
            d = rdata;
            @(negedge clk); rready = 0; arvalid = 0;
        end
    endtask

    function [31:0] crc32_next(input [31:0] crc, input [7:0] b);
        integer i;
        reg [31:0] c;
        begin
            c = crc ^ {24'd0, b};
            for (i = 0; i < 8; i = i + 1) c = c[0] ? (c >> 1) ^ 32'hEDB88320 : (c >> 1);
            crc32_next = c;
        end
    endfunction

    localparam N = 64;
    reg [7:0] payload [0:N-1];
    reg [7:0] cap [0:255];
    integer cap_n = 0;
    reg [31:0] v, crc;
    integer i, k;

    // GMII transmit monitor on the TX clock (= rxclk for this PHY core)
    always @(posedge rxclk) if (tx_en && cap_n < 256) begin cap[cap_n] = tx_data; cap_n = cap_n + 1; end

    task send_frame(input corrupt);
        reg [31:0] c;
        integer j;
        begin
            c = 32'hFFFFFFFF;
            for (j = 0; j < N; j = j + 1) c = crc32_next(c, payload[j]);
            c = ~c;
            @(posedge rxclk);
            for (j = 0; j < 8; j = j + 1) begin
                #1 rx_data = (j == 7) ? 8'hD5 : 8'h55; rx_dv = 1;
                @(posedge rxclk);
            end
            for (j = 0; j < N; j = j + 1) begin
                #1 rx_data = (corrupt && j == 10) ? ~payload[j] : payload[j];
                @(posedge rxclk);
            end
            for (j = 0; j < 4; j = j + 1) begin
                #1 rx_data = c[8 * j +: 8];
                @(posedge rxclk);
            end
            #1 rx_dv = 0; rx_data = 0;
            repeat (30) @(posedge rxclk);
        end
    endtask

    initial begin
        for (i = 0; i < N; i = i + 1) payload[i] = 8'h30 + i * 7;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (400) @(posedge clk); // PHY hardware reset counter (256 cycles)
        check(rst_n === 1'b1, "PHY reset released");

        // ---- AXI-Lite channel skew: write the RX event enable register and read it back
        for (i = 0; i < 6; i = i + 1) begin
            axi_wr_skew(CSR + W_EN, 0, 0, i);          // AW first, W i cycles later
            axi_rd(CSR + W_EN, v); check(v[0] == 1'b0, "skewed write (AW first) cleared enable");
            axi_wr_skew(CSR + W_EN, 1, i, 0);          // W first, AW i cycles later
            axi_rd(CSR + W_EN, v); check(v[0] == 1'b1, "skewed write (W first) set enable");
        end
        axi_wr(CSR + W_EN, 0);

        // ---- transmit
        for (i = 0; i < N / 4; i = i + 1)
            axi_wr(TXBUF + 4 * i, {payload[4*i+3], payload[4*i+2], payload[4*i+1], payload[4*i]});
        axi_rd(CSR + R_READY, v); check(v[0] == 1'b1, "reader ready before start");
        axi_wr(CSR + R_SLOT, 0);
        axi_wr(CSR + R_LEN, N);
        axi_wr(CSR + R_START, 1);
        repeat (200) @(posedge rxclk);
        check(cap_n == 8 + N + 4, "transmitted frame length (preamble+SFD+payload+CRC)");
        for (k = 0; k < 7; k = k + 1) check(cap[k] == 8'h55, "preamble byte");
        check(cap[7] == 8'hD5, "start of frame delimiter");
        for (k = 0; k < N; k = k + 1) check(cap[8 + k] == payload[k], "payload byte on GMII");
        crc = 32'hFFFFFFFF;
        for (k = 0; k < N; k = k + 1) crc = crc32_next(crc, payload[k]);
        crc = ~crc;
        for (k = 0; k < 4; k = k + 1) check(cap[8 + N + k] == crc[8 * k +: 8], "CRC-32 byte (little end first)");
        check(tx_er === 1'b0, "TX_ER stays low");
        axi_rd(CSR + R_READY, v); check(v[0] == 1'b1, "reader ready again after the frame");

        // ---- receive, good frame
        axi_wr(CSR + W_EN, 1);
        axi_rd(CSR + W_PEND, v); check(v[0] == 1'b0, "no RX event before a frame");
        check(irq === 1'b0, "interrupt low before a frame");
        send_frame(1'b0);
        repeat (50) @(posedge clk);
        check(irq === 1'b1, "interrupt after a good frame");
        axi_rd(CSR + W_PEND, v); check(v[0] == 1'b1, "RX event pending");
        axi_rd(CSR + W_SLOT, v); check(v[7:0] == 8'd0, "frame lands in slot 0");
        axi_rd(CSR + W_LEN, v); check(v == N, "RX length excludes preamble and CRC");
        for (i = 0; i < N / 4; i = i + 1) begin
            axi_rd(RXBUF + 4 * i, v);
            check(v == {payload[4*i+3], payload[4*i+2], payload[4*i+1], payload[4*i]}, "RX buffer word");
        end
        axi_wr(CSR + W_PEND, 1);
        axi_rd(CSR + W_PEND, v); check(v[0] == 1'b0, "RX event cleared");
        check(irq === 1'b0, "interrupt cleared");

        // ---- receive, corrupted payload (bad CRC)
        axi_rd(CSR + CRC_ERR, v);
        k = v;
        send_frame(1'b1);
        repeat (50) @(posedge clk);
        axi_rd(CSR + CRC_ERR, v); check(v == k + 1, "CRC error counted");
        axi_rd(CSR + W_PEND, v); check(v[0] == 1'b0, "bad frame raises no RX event");

        // ---- second good frame goes to the next slot
        send_frame(1'b0);
        repeat (50) @(posedge clk);
        axi_rd(CSR + W_SLOT, v); check(v[7:0] == 8'd1, "next good frame lands in slot 1");

        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
    initial begin
        #3000000;
        $display("TBRESULT checks=%0d errors=%0d FAIL (watchdog)", checks, errors + 1);
        $finish;
    end
endmodule
