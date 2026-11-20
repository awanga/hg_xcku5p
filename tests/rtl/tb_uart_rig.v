// SPDX-License-Identifier: MIT
// Bench for uart_rig (with uart_rx and uart_tx): a UART host model sends command lines; behavioural AXI4-Lite (peripheral) and AXI4 256-bit (memory) slaves
// hold word arrays so the expected values come from the test, not from the DUT. Monitors check the AXI side signals the contract fixes (prot, strobes, length,
// size, burst, last) and count transactions per port. Response lines are collected from the tx pin.
`timescale 1ns/1ps
module tb_uart_rig;
    localparam CPB = 32;                  // clocks per bit (small, for simulation speed)
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------- DUT
    reg         rx = 1;
    wire        tx;
    reg  [31:0] irq_in = 32'h0000_0A5C;
    wire [31:0] p_awaddr, p_wdata, p_araddr, p_rdata;
    wire [2:0]  p_awprot, p_arprot;
    wire [3:0]  p_wstrb;
    wire        p_awvalid, p_wvalid, p_bready, p_arvalid, p_rready;
    wire        p_awready, p_wready, p_bvalid, p_arready, p_rvalid;
    wire [1:0]  p_bresp, p_rresp;
    wire [31:0] m_awaddr, m_araddr, m_wstrb;
    wire [7:0]  m_awlen, m_arlen;
    wire [2:0]  m_awsize, m_arsize;
    wire [1:0]  m_awburst, m_arburst, m_bresp, m_rresp;
    wire [255:0] m_wdata, m_rdata;
    wire        m_awvalid, m_wlast, m_wvalid, m_bready, m_arvalid, m_rready;
    wire        m_awready, m_wready, m_bvalid, m_arready, m_rvalid;

    uart_rig #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst_n(rst_n), .rx(rx), .tx(tx), .irq_in(irq_in),
        .p_awaddr(p_awaddr), .p_awprot(p_awprot), .p_awvalid(p_awvalid), .p_awready(p_awready), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_wvalid(p_wvalid), .p_wready(p_wready), .p_bresp(p_bresp), .p_bvalid(p_bvalid), .p_bready(p_bready),
        .p_araddr(p_araddr), .p_arprot(p_arprot), .p_arvalid(p_arvalid), .p_arready(p_arready), .p_rdata(p_rdata), .p_rresp(p_rresp),
        .p_rvalid(p_rvalid), .p_rready(p_rready),
        .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rvalid(m_rvalid), .m_rready(m_rready));

    // ---------------------------------------------------------------- peripheral slave (AXI4-Lite): 16 words at addr[5:2]; 0xF8000FF0 answers SLVERR
    parameter LAT = 3;
    reg [31:0] pm [0:15];
    reg        p_awr = 0, p_wr = 0, p_arr = 0, p_aws = 0, p_ws = 0, p_bv = 0, p_rv = 0;
    reg [1:0]  p_br = 0, p_rr = 0;
    reg [31:0] p_a = 0, p_d = 0, p_rd = 0;
    reg [3:0]  p_s = 0;
    integer    p_dly = 0;
    integer    p_aw_n = 0, p_ar_n = 0;
    reg [31:0] p_last_aw = 0, p_last_ar = 0;
    assign p_awready = p_awr, p_wready = p_wr, p_arready = p_arr, p_bvalid = p_bv, p_bresp = p_br, p_rvalid = p_rv, p_rresp = p_rr, p_rdata = p_rd;
    always @(posedge clk) begin
        p_awr <= p_awvalid && !p_awr && !p_aws;
        p_wr <= p_wvalid && !p_wr && !p_ws;
        if (p_awvalid && p_awr) begin p_a <= p_awaddr; p_aws <= 1; p_aw_n <= p_aw_n + 1; p_last_aw <= p_awaddr; end
        if (p_wvalid && p_wr) begin p_d <= p_wdata; p_s <= p_wstrb; p_ws <= 1; end
        if (p_aws && p_ws && !p_bv) begin
            p_bv <= 1;
            if (p_a == 32'hF8000FF0) p_br <= 2'b10;
            else begin
                p_br <= 2'b00;
                pm[p_a[5:2]] <= p_d;
            end
            p_aws <= 0;
            p_ws <= 0;
        end
        if (p_bv && p_bready) p_bv <= 0;
        p_arr <= p_arvalid && !p_arr && !p_rv && p_dly == 0;
        if (p_arvalid && p_arr) begin
            p_ar_n <= p_ar_n + 1; p_last_ar <= p_araddr;
            p_dly <= LAT;
            p_rd <= (p_araddr == 32'hF8000FF0) ? 32'hBAD0BAD0 : pm[p_araddr[5:2]];
            p_rr <= (p_araddr == 32'hF8000FF0) ? 2'b10 : 2'b00;
        end
        if (p_dly > 0) begin
            p_dly <= p_dly - 1;
            if (p_dly == 1) p_rv <= 1;
        end
        if (p_rv && p_rready) p_rv <= 0;
    end

    // ---------------------------------------------------------------- memory slave (AXI4, 256 bit): 64 words at addr[10:5]; 0x40000FE0 (word 0x3F) answers SLVERR
    reg [255:0] mm [0:63];
    reg         m_awr = 0, m_wr = 0, m_arr = 0, m_aws = 0, m_ws = 0, m_bv = 0, m_rv = 0;
    reg [1:0]   m_br = 0, m_rr = 0;
    reg [31:0]  m_a = 0, m_s = 0;
    reg [255:0] m_d = 0, m_rd = 0;
    integer     m_dly = 0;
    integer     m_aw_n = 0, m_ar_n = 0, proto_err = 0;
    reg [31:0]  m_last_s = 0, m_last_aw = 0, m_last_ar = 0;
    integer     k;
    assign m_awready = m_awr, m_wready = m_wr, m_arready = m_arr, m_bvalid = m_bv, m_bresp = m_br, m_rvalid = m_rv, m_rresp = m_rr, m_rdata = m_rd;
    always @(posedge clk) begin
        m_awr <= m_awvalid && !m_awr && !m_aws;
        m_wr <= m_wvalid && !m_wr && !m_ws;
        if (m_awvalid && m_awr) begin m_a <= m_awaddr; m_aws <= 1; m_aw_n <= m_aw_n + 1; m_last_aw <= m_awaddr; end
        if (m_wvalid && m_wr) begin m_d <= m_wdata; m_s <= m_wstrb; m_ws <= 1; m_last_s <= m_wstrb; end
        if (m_aws && m_ws && !m_bv) begin
            m_bv <= 1;
            if (m_a == 32'h40000FE0) m_br <= 2'b10;
            else begin
                m_br <= 2'b00;
                for (k = 0; k < 32; k = k + 1)
                    if (m_s[k]) mm[m_a[10:5]][8*k +: 8] <= m_d[8*k +: 8];
            end
            m_aws <= 0;
            m_ws <= 0;
        end
        if (m_bv && m_bready) m_bv <= 0;
        m_arr <= m_arvalid && !m_arr && !m_rv && m_dly == 0;
        if (m_arvalid && m_arr) begin
            m_ar_n <= m_ar_n + 1; m_last_ar <= m_araddr;
            m_dly <= LAT;
            m_rd <= mm[m_araddr[10:5]];
            m_rr <= (m_araddr == 32'h40000FE0) ? 2'b10 : 2'b00;
        end
        if (m_dly > 0) begin
            m_dly <= m_dly - 1;
            if (m_dly == 1) m_rv <= 1;
        end
        if (m_rv && m_rready) m_rv <= 0;
    end

    // protocol monitors
    always @(posedge clk) if (rst_n) begin
        if (p_awvalid && p_awprot != 0) proto_err = proto_err + 1;
        if (p_arvalid && p_arprot != 0) proto_err = proto_err + 1;
        if (p_wvalid && p_wstrb != 4'hF) proto_err = proto_err + 1;
        if (m_awvalid && (m_awlen != 0 || m_awsize != 3'd2 || m_awburst != 2'b01)) proto_err = proto_err + 1;
        if (m_arvalid && (m_arlen != 0 || m_arsize != 3'd2 || m_arburst != 2'b01)) proto_err = proto_err + 1;
        if (m_wvalid && !m_wlast) proto_err = proto_err + 1;
        if (m_wvalid && (m_wstrb & (m_wstrb - 1)) == 0) proto_err = proto_err + 1;   // a word write sets four strobes, never fewer
    end

    // ---------------------------------------------------------------- host model
    integer hbit = CPB;                  // host bit time in clocks (varied for the tolerance test)
    task sendb(input [7:0] b);
        integer i;
        begin
            rx = 0; repeat (hbit) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i]; repeat (hbit) @(posedge clk);
            end
            rx = 1; repeat (hbit) @(posedge clk);
        end
    endtask
    task send_bad_stop(input [7:0] b);   // a frame whose stop bit is low
        integer i;
        begin
            rx = 0; repeat (CPB) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i]; repeat (CPB) @(posedge clk);
            end
            rx = 0; repeat (CPB) @(posedge clk);
            rx = 1; repeat (CPB) @(posedge clk);
        end
    endtask
    task sline(input [8*48-1:0] s, input integer n);   // the n last characters of s, then LF
        integer i;
        begin
            for (i = n - 1; i >= 0; i = i - 1) sendb(s[8*i +: 8]);
            sendb(8'h0A);
        end
    endtask

    // received characters
    reg [7:0] rb [0:4095];
    integer   rn = 0, rd_ptr = 0;
    integer   rcv;
    always @(negedge tx) begin : cap
        integer i;
        reg [7:0] c;
        #(CPB * 10 / 2 + 1);
        c = 0;
        for (i = 0; i < 8; i = i + 1) begin
            #(CPB * 10);
            c[i] = tx;
        end
        #(CPB * 10);
        rb[rn] = c;
        rn = rn + 1;
    end

    integer checks = 0, errors = 0;
    task chk(input ok, input [8*60-1:0] what);
        begin
            checks = checks + 1;
            if (!ok) begin
                errors = errors + 1;
                $display("FAIL: %0s", what);
            end
        end
    endtask

    // wait for one response line, compare with the n last chars of exp (no LF in exp)
    task expect_line(input [8*12-1:0] exp, input integer n, input [8*60-1:0] what);
        integer i, t;
        reg okk;
        begin
            t = 0;
            while (!(rn > rd_ptr && rb[rn-1] == 8'h0A) && t < 400000) begin @(posedge clk); t = t + 1; end
            // let the line settle (a second line would show as extra characters)
            if (t >= 400000) begin chk(0, what); rd_ptr = rn; end
            else begin
                okk = (rn - rd_ptr == n + 1);
                for (i = 0; i < n && okk; i = i + 1)
                    if (rb[rd_ptr + i] != exp[8*(n-1-i) +: 8]) okk = 0;
                chk(okk, what);
                if (!okk) $display("  got %0d chars: %c%c%c%c%c%c%c%c%c", rn - rd_ptr, rb[rd_ptr], rb[rd_ptr+1], rb[rd_ptr+2], rb[rd_ptr+3],
                    rb[rd_ptr+4], rb[rd_ptr+5], rb[rd_ptr+6], rb[rd_ptr+7], rb[rd_ptr+8]);
                rd_ptr = rn;
            end
        end
    endtask
    task expect_quiet(input [8*60-1:0] what);   // no response at all within a few character times
        begin
            repeat (CPB * 10 * 6) @(posedge clk);
            chk(rn == rd_ptr, what);
            rd_ptr = rn;
        end
    endtask

    integer i;
    reg [31:0] v;
    initial begin
        if ($test$plusargs("vcd")) begin $dumpfile("tb_uart_rig.vcd"); $dumpvars(0, tb_uart_rig); end
        for (i = 0; i < 16; i = i + 1) pm[i] = 32'h1000_0000 + i;
        for (i = 0; i < 64; i = i + 1) mm[i] = 256'd0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (20) @(posedge clk);

        // identification and the interrupt vector
        sline("V", 1);                        expect_line("HGRIG1", 6, "V identifies");
        sline("I", 1);                        expect_line("00000A5C", 8, "I returns irq_in");
        irq_in = 32'hDEADBEEF;
        sline("i", 1);                        expect_line("DEADBEEF", 8, "I follows irq_in, lower-case command");

        // peripheral words
        sline("W F8000010 DEADBEEF", 19);     expect_line("OK", 2, "peripheral write answers OK");
        chk(pm[4] == 32'hDEADBEEF, "peripheral write reached the slave word");
        chk(p_last_aw == 32'hF8000010, "peripheral write address");
        sline("R F8000010", 10);              expect_line("DEADBEEF", 8, "peripheral read");
        sline("r f8000014", 10);              expect_line("10000005", 8, "lower-case read of an untouched word");
        sline("W 10000 1", 9);                expect_line("OK", 2, "short numbers, address 0x10000 is peripheral word 0");
        chk(pm[0] == 32'h1 && p_last_aw == 32'h10000, "short number values");
        sline("W\tF8000018   \t0000CAFE  ", 24); expect_line("OK", 2, "tabs and extra spaces");
        chk(pm[6] == 32'hCAFE, "tab separated write value");

        // memory words: each lane of a 256-bit word, independent expected layout
        for (i = 0; i < 8; i = i + 1) begin
            v = 32'hA0000000 + 32'h01010101 * i;
            case (i)
            0: sline("W 40000000 A0000000", 19);
            1: sline("W 40000004 A1010101", 19);
            2: sline("W 40000008 A2020202", 19);
            3: sline("W 4000000C A3030303", 19);
            4: sline("W 40000010 A4040404", 19);
            5: sline("W 40000014 A5050505", 19);
            6: sline("W 40000018 A6060606", 19);
            7: sline("W 4000001C A7070707", 19);
            endcase
            expect_line("OK", 2, "memory lane write answers OK");
            chk(m_last_s == (32'h0000000F << (4 * i)), "memory write strobe selects lane");
            chk(mm[0][32*i +: 32] == v, "memory lane holds the word");
        end
        chk(mm[0] == {32'hA7070707, 32'hA6060606, 32'hA5050505, 32'hA4040404, 32'hA3030303, 32'hA2020202, 32'hA1010101, 32'hA0000000},
            "memory word has all eight lanes and nothing else");
        sline("R 4000001C", 10);              expect_line("A7070707", 8, "memory read lane 7");
        sline("R 40000000", 10);              expect_line("A0000000", 8, "memory read lane 0");
        sline("W 40000020 11223344", 19);     expect_line("OK", 2, "second memory word");
        chk(mm[1] == 256'h11223344, "memory word 1 lane 0 only");
        sline("W 7FFFFFFC 55667788", 19);     expect_line("OK", 2, "top of the memory window");
        chk(mm[63][255:224] == 32'h55667788 && m_last_aw == 32'h7FFFFFFC, "memory word 63 lane 7");
        sline("R 7FFFFFFC", 10);              expect_line("55667788", 8, "top of the window readback");
        // regions around the memory window go to the peripheral port
        i = m_aw_n;
        sline("W 80000000 12345678", 19);     expect_line("OK", 2, "0x80000000 is peripheral");
        chk(m_aw_n == i && p_last_aw == 32'h80000000 && pm[0] == 32'h12345678, "0x80000000 reached the peripheral port only");
        sline("W 3FFFFFFC 0BADF00D", 19);     expect_line("OK", 2, "0x3FFFFFFC is peripheral");
        chk(m_aw_n == i && p_last_aw == 32'h3FFFFFFC && pm[15] == 32'h0BADF00D, "0x3FFFFFFC reached the peripheral port only");

        // bus errors, then recovery
        sline("W F8000FF0 1", 12);            expect_line("ERR", 3, "peripheral write error");
        sline("R F8000FF0", 10);              expect_line("ERR", 3, "peripheral read error");
        sline("W 40000FE0 1", 12);            expect_line("ERR", 3, "memory write error");
        sline("R 40000FE0", 10);              expect_line("ERR", 3, "memory read error");
        sline("R F8000010", 10);              expect_line("DEADBEEF", 8, "bus works after errors");

        // burst reads
        sline("B 40000000 A", 12);            // words 0..9: eight lanes of word 0, then word 1 lane 0 and the zeros of lane 1
        expect_line("A0000000", 8, "burst word 0");
        expect_line("A1010101", 8, "burst word 1");
        expect_line("A2020202", 8, "burst word 2");
        expect_line("A3030303", 8, "burst word 3");
        expect_line("A4040404", 8, "burst word 4");
        expect_line("A5050505", 8, "burst word 5");
        expect_line("A6060606", 8, "burst word 6");
        expect_line("A7070707", 8, "burst word 7");
        expect_line("11223344", 8, "burst word 8 is lane 0 of memory word 1");
        expect_line("00000000", 8, "burst word 9 is lane 1 of memory word 1");
        sline("B f8000010 3", 12);
        expect_line("DEADBEEF", 8, "peripheral burst 0");
        expect_line("10000005", 8, "peripheral burst 1");
        expect_line("0000CAFE", 8, "peripheral burst 2");
        sline("B F8000FE8 4", 12);            // FE8, FEC fine, FF0 is an error: two lines, then ERR, nothing after
        expect_line("1000000A", 8, "error burst word 0 (0xF8000FE8, index 10)");
        expect_line("1000000B", 8, "error burst word 1 (0xF8000FEC, index 11)");
        expect_line("ERR", 3, "error burst stops with ERR");
        expect_quiet("error burst stops");
        sline("B 3FFFFFF8 4", 12);            // the burst crosses from the peripheral port into memory
        expect_line("1000000E", 8, "crossing burst: 0x3FFFFFF8 (index 14)");
        expect_line("0BADF00D", 8, "crossing burst: 0x3FFFFFFC");
        expect_line("A0000000", 8, "crossing burst: memory 0x40000000");
        expect_line("A1010101", 8, "crossing burst: memory 0x40000004");
        sline("B f8000010 1", 12);            expect_line("DEADBEEF", 8, "single-word burst");

        // malformed lines answer ERR and the next good one still works
        sline("X", 1);                        expect_line("ERR", 3, "unknown command");
        sline("W 1", 3);                      expect_line("ERR", 3, "write with one argument");
        sline("W 1 2 3", 7);                  expect_line("ERR", 3, "write with three arguments");
        sline("R", 1);                        expect_line("ERR", 3, "read without address");
        sline("R 1F8001000", 11);             expect_line("ERR", 3, "nine digits (the low eight alone would be a valid address)");
        sline("R 1G", 4);                     expect_line("ERR", 3, "non-hex character");
        sline("R F8000012", 10);              expect_line("ERR", 3, "unaligned read");
        sline("W F8000011 5", 12);            expect_line("ERR", 3, "unaligned write");
        sline("B 0 0", 5);                    expect_line("ERR", 3, "zero count");
        sline("B 0 10000", 9);                expect_line("ERR", 3, "count above FFFF");
        sline("B F8000010", 10);              expect_line("ERR", 3, "burst without count");
        sline("I 5", 3);                      expect_line("ERR", 3, "I with an argument");
        sline("V 1", 3);                      expect_line("ERR", 3, "V with an argument");
        sline("R F8000010", 10);              expect_line("DEADBEEF", 8, "valid read after malformed lines");
        chk(pm[4] == 32'hDEADBEEF, "malformed writes changed nothing");

        // line endings and blank lines
        sendb(8'h0A); sendb(8'h0D); sendb(8'h0A);
        expect_quiet("blank lines are ignored");
        sendb("R"); sendb(" "); sline("F8000010", 8);   // CR before LF is ignored
        sendb(8'h0D);
        expect_line("DEADBEEF", 8, "read after blank lines");
        sendb("R"); sendb(" "); sendb("F"); sendb("8"); sendb("0"); sendb("0"); sendb("0"); sendb("0"); sendb("1"); sendb("0"); sendb(8'h0D); sendb(8'h0A);
        expect_line("DEADBEEF", 8, "CR LF line ending");

        // a frame with a bad stop bit is dropped
        send_bad_stop(8'h55);
        expect_quiet("bad stop bit gives no output");
        sline("R F8000010", 10);              expect_line("DEADBEEF", 8, "line after a framing error");

        // bytes that arrive while a command runs are dropped
        i = p_ar_n;
        sendb("R"); sendb(" "); sendb("F"); sendb("8"); sendb("0"); sendb("0"); sendb("0"); sendb("0"); sendb("1"); sendb("0"); sendb(8'h0A);
        sendb("V"); sendb(8'h0A);             // sent while the reply is still on the line
        expect_line("DEADBEEF", 8, "reply of the first command");
        expect_quiet("the line sent during the reply is dropped");
        chk(p_ar_n == i + 1, "exactly one peripheral read for the two lines");

        // host baud error of about +-3 percent
        hbit = CPB - 1;
        sline("R F8000010", 10);              expect_line("DEADBEEF", 8, "host 3 percent fast");
        hbit = CPB + 1;
        sline("R F8000010", 10);              expect_line("DEADBEEF", 8, "host 3 percent slow");
        hbit = CPB;

        chk(proto_err == 0, "AXI side protocol: prot, strobes, length, size, burst, last");
        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (checks > 0 && errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
