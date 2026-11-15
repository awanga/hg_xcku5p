// SPDX-License-Identifier: MIT
// vpcie + pcie_regs: a host-bridge master drives the 2 MiB window (ECAM below 0xF9100000, BAR window above); a CPU master drives the pcie_regs CPU port.
// Expected values come from the register map in the vpcie.v / pcie_regs.v headers and the PCI header layout, not from the DUT.
`timescale 1ns / 1ps
module tb_vpcie;
    parameter RDLY = 0;   // cycles the host master waits before BREADY / RREADY
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    localparam [31:0] BASE = 32'hF9000000;

    // host bridge master
    reg  [20:0] s_awaddr = 21'd0, s_araddr = 21'd0;
    reg  [31:0] s_wdata = 32'd0;
    reg  [3:0]  s_wstrb = 4'hF;
    reg         s_awvalid = 1'b0, s_wvalid = 1'b0, s_arvalid = 1'b0, s_bready = 1'b0, s_rready = 1'b0;
    wire        s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [1:0]  s_bresp, s_rresp;
    wire [31:0] s_rdata;
    // vpcie -> pcie_regs host port
    wire [6:0]  m_awaddr, m_araddr;
    wire [31:0] m_wdata, m_rdata;
    wire [3:0]  m_wstrb;
    wire        m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready, m_arvalid, m_arready, m_rvalid, m_rready;
    wire [1:0]  m_bresp, m_rresp;
    // CPU master
    reg  [6:0]  c_awaddr = 7'd0, c_araddr = 7'd0;
    reg  [31:0] c_wdata = 32'd0;
    reg         c_awvalid = 1'b0, c_wvalid = 1'b0, c_arvalid = 1'b0;
    wire        c_awready, c_wready, c_bvalid, c_arready, c_rvalid;
    wire [31:0] c_rdata;
    wire [31:0] win_base, win_size;
    wire        irq, cpu_db_any, intx;
    reg         tog = 1'b0;
    always @(posedge clk) tog <= ~tog;

    pcie_regs regs (.clk(clk), .rst_n(rst_n),
        .h_awaddr(m_awaddr), .h_awvalid(m_awvalid), .h_awready(m_awready), .h_wdata(m_wdata), .h_wstrb(m_wstrb), .h_wvalid(m_wvalid),
        .h_wready(m_wready), .h_bresp(m_bresp), .h_bvalid(m_bvalid), .h_bready(m_bready), .h_araddr(m_araddr), .h_arvalid(m_arvalid),
        .h_arready(m_arready), .h_rdata(m_rdata), .h_rresp(m_rresp), .h_rvalid(m_rvalid), .h_rready(m_rready),
        .c_awaddr(c_awaddr), .c_awvalid(c_awvalid), .c_awready(c_awready), .c_wdata(c_wdata), .c_wstrb(4'hF), .c_wvalid(c_wvalid),
        .c_wready(c_wready), .c_bresp(), .c_bvalid(c_bvalid), .c_bready(1'b1), .c_araddr(c_araddr), .c_arvalid(c_arvalid),
        .c_arready(c_arready), .c_rdata(c_rdata), .c_rresp(), .c_rvalid(c_rvalid), .c_rready(1'b1),
        .link_up_a(1'b1), .aclk_toggle_a(tog), .perst_n_a(1'b1), .win_base(win_base), .win_size(win_size), .irq(irq), .cpu_db_any(cpu_db_any));

    vpcie #(.BASE(BASE)) dut (.clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid),
        .s_wready(s_wready), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready), .s_araddr(s_araddr), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wvalid(m_wvalid),
        .m_wready(m_wready), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready), .m_araddr(m_araddr), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rvalid(m_rvalid), .m_rready(m_rready),
        .intx_pending(cpu_db_any), .intx(intx));

    integer errors = 0, checks = 0, i;
    reg [31:0] rd_val;

    task hw(input [20:0] a, input [31:0] d, input [3:0] strb);
        begin
            @(negedge clk);
            s_awaddr = a; s_wdata = d; s_wstrb = strb; s_awvalid = 1'b1;
            @(posedge clk); while (!s_awready) @(posedge clk);
            @(negedge clk); s_awvalid = 1'b0; s_wvalid = 1'b1;
            @(posedge clk); while (!s_wready) @(posedge clk);
            @(negedge clk); s_wvalid = 1'b0;
            repeat (RDLY) @(posedge clk);
            #1 s_bready = 1'b1;
            @(posedge clk); while (!s_bvalid) @(posedge clk);
            if (s_bresp !== 2'b00) begin errors = errors + 1; $display("FAIL bresp"); end
            @(negedge clk); s_bready = 1'b0;
        end
    endtask
    task hr(input [20:0] a);
        begin
            @(negedge clk); s_araddr = a; s_arvalid = 1'b1;
            @(posedge clk); while (!s_arready) @(posedge clk);
            @(negedge clk); s_arvalid = 1'b0;
            repeat (RDLY) @(posedge clk);
            #1 s_rready = 1'b1;
            @(posedge clk); while (!s_rvalid) @(posedge clk);
            #1 rd_val = s_rdata;
            if (s_rresp !== 2'b00) begin errors = errors + 1; $display("FAIL rresp"); end
            @(negedge clk); s_rready = 1'b0;
        end
    endtask
    task cw(input [6:0] a, input [31:0] d);
        begin
            @(negedge clk); c_awaddr = a; c_wdata = d; c_awvalid = 1'b1; c_wvalid = 1'b1;
            @(posedge clk); while (!(c_awready && c_wready)) @(posedge clk);
            @(negedge clk); c_awvalid = 1'b0; c_wvalid = 1'b0;
            @(posedge clk); while (!c_bvalid) @(posedge clk);
        end
    endtask
    task cr(input [6:0] a);
        begin
            @(negedge clk); c_araddr = a; c_arvalid = 1'b1;
            @(posedge clk); while (!c_arready) @(posedge clk);
            @(negedge clk); c_arvalid = 1'b0;
            @(posedge clk); while (!c_rvalid) @(posedge clk);
            #1 rd_val = c_rdata;
        end
    endtask
    task expect_v(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL %0s: got %08x want %08x", what, got, want);
            end
        end
    endtask
    task cfg_rd(input [7:0] devfn, input [9:0] dw);   // ECAM read
        hr({1'b0, devfn, dw, 2'b00});
    endtask
    task cfg_wr(input [7:0] devfn, input [9:0] dw, input [31:0] d, input [3:0] strb);
        hw({1'b0, devfn, dw, 2'b00}, d, strb);
    endtask

    initial begin
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // identity and reset state of 00:00.0 (PCI header layout)
        cfg_rd(8'h00, 10'h00); expect_v("vendor/device", rd_val, 32'h903410EE);
        cfg_rd(8'h00, 10'h01); expect_v("command/status reset", rd_val, 32'h00000000);
        cfg_rd(8'h00, 10'h02); expect_v("class", rd_val, 32'h05800000);
        cfg_rd(8'h00, 10'h03); expect_v("header type", rd_val, 32'h00000000);
        cfg_rd(8'h00, 10'h04); expect_v("BAR0 reset", rd_val, 32'h00000000);
        cfg_rd(8'h00, 10'h05); expect_v("BAR1", rd_val, 32'h00000000);
        cfg_rd(8'h00, 10'h0B); expect_v("subsystem", rd_val, 32'h000710EE);
        cfg_rd(8'h00, 10'h0D); expect_v("capability pointer", rd_val, 32'h00000000);
        cfg_rd(8'h00, 10'h0F); expect_v("interrupt pin", rd_val, 32'h00000100);
        // absent functions: master abort
        cfg_rd(8'h01, 10'h00); expect_v("fn1 absent", rd_val, 32'hFFFFFFFF);
        cfg_rd(8'h08, 10'h00); expect_v("dev1 absent", rd_val, 32'hFFFFFFFF);
        cfg_rd(8'hF8, 10'h01); expect_v("dev31 absent", rd_val, 32'hFFFFFFFF);
        cfg_wr(8'h01, 10'h01, 32'h00000006, 4'hF);
        cfg_wr(8'h08, 10'h01, 32'h00000006, 4'hF);
        cfg_rd(8'h00, 10'h01); expect_v("absent write ignored", rd_val, 32'h00000000);
        // read-only fields
        cfg_wr(8'h00, 10'h00, 32'h00000000, 4'hF); cfg_rd(8'h00, 10'h00); expect_v("ID read-only", rd_val, 32'h903410EE);
        cfg_wr(8'h00, 10'h02, 32'hFFFFFFFF, 4'hF); cfg_rd(8'h00, 10'h02); expect_v("class read-only", rd_val, 32'h05800000);
        cfg_wr(8'h00, 10'h05, 32'hFFFFFFFF, 4'hF); cfg_rd(8'h00, 10'h05); expect_v("BAR1 read-only", rd_val, 32'h00000000);
        // BAR sizing and assignment
        cfg_wr(8'h00, 10'h04, 32'hFFFFFFFF, 4'hF); cfg_rd(8'h00, 10'h04); expect_v("BAR0 sizing mask", rd_val, 32'hFFFF0000);
        cfg_wr(8'h00, 10'h04, 32'hF9120000, 4'hF); cfg_rd(8'h00, 10'h04); expect_v("BAR0 assigned", rd_val, 32'hF9120000);
        cfg_wr(8'h00, 10'h04, 32'h00000000, 4'h4); cfg_rd(8'h00, 10'h04); expect_v("BAR0 byte 2 only", rd_val, 32'hF9000000);
        cfg_wr(8'h00, 10'h04, 32'hF9120000, 4'hC); cfg_rd(8'h00, 10'h04); expect_v("BAR0 upper half", rd_val, 32'hF9120000);
        // memory disabled: the BAR window master-aborts
        cw(7'h20, 32'h11111111);   // the mailbox has no reset value
        hw(21'h120020, 32'hDEADBEEF, 4'hF);
        cr(7'h20); expect_v("mailbox after dropped write", rd_val, 32'h11111111);
        hr(21'h120000); expect_v("window read, memory disabled", rd_val, 32'hFFFFFFFF);
        // enable memory decoding (byte write of the low command byte)
        cfg_wr(8'h00, 10'h01, 32'h00000002, 4'h1); cfg_rd(8'h00, 10'h01); expect_v("command mem", rd_val, 32'h00000002);
        hr(21'h120000); expect_v("BAR0 +0 reads the register block ID", rd_val, 32'h50434901);
        hr(21'h120004); expect_v("BAR0 STATUS: link, clock, PERST# up", rd_val & 32'h7, 32'h7);
        hw(21'h120020, 32'hA5A55A5A, 4'hF);
        cr(7'h20); expect_v("mailbox written by the host side", rd_val, 32'hA5A55A5A);
        cw(7'h24, 32'h12345678);
        hr(21'h120024); expect_v("mailbox written by the CPU side", rd_val, 32'h12345678);
        // outside BAR0: aborted
        hr(21'h110000); expect_v("below BAR0", rd_val, 32'hFFFFFFFF);
        hr(21'h130000); expect_v("above BAR0", rd_val, 32'hFFFFFFFF);
        hr(21'h1FFFFC); expect_v("end of window", rd_val, 32'hFFFFFFFF);
        hw(21'h130020, 32'h0BADF00D, 4'hF);
        cr(7'h20); expect_v("write above BAR0 dropped", rd_val, 32'hA5A55A5A);
        // doorbells and INTx
        cfg_rd(8'h00, 10'h01); expect_v("no INTx pending", rd_val[31:16], 16'h0000);
        expect_v("intx low", {31'd0, intx}, 32'd0);
        cw(7'h0C, 32'h00000001);   // CPU rings the host
        repeat (3) @(posedge clk);
        expect_v("intx high", {31'd0, intx}, 32'd1);
        cfg_rd(8'h00, 10'h01); expect_v("status INTx bit", rd_val[31:16] & 16'h0008, 32'h0008);
        cfg_wr(8'h00, 10'h01, 32'h00000400, 4'h2);   // INTx disable
        cfg_rd(8'h00, 10'h01); expect_v("command INTx disable keeps mem", rd_val[15:0], 32'h00000402);
        cfg_rd(8'h00, 10'h01); expect_v("status INTx bit stays", rd_val[31:16] & 16'h0008, 32'h0008);
        expect_v("intx masked", {31'd0, intx}, 32'd0);
        cfg_wr(8'h00, 10'h01, 32'h00000000, 4'h2);   // enable again
        expect_v("intx unmasked", {31'd0, intx}, 32'd1);
        hw(21'h12000C, 32'h00000001, 4'hF);          // host acknowledges
        repeat (3) @(posedge clk);
        expect_v("intx cleared by the host", {31'd0, intx}, 32'd0);
        // memory enable off again
        cfg_wr(8'h00, 10'h01, 32'h00000004, 4'h3); cfg_rd(8'h00, 10'h01); expect_v("command bus master only", rd_val[15:0], 32'h00000004);
        hr(21'h120000); expect_v("memory disabled again", rd_val, 32'hFFFFFFFF);
        cfg_wr(8'h00, 10'h01, 32'h00000002, 4'h3);
        // moving the BAR
        cfg_wr(8'h00, 10'h04, 32'hF9130000, 4'hF);
        hr(21'h120000); expect_v("old BAR address no longer decodes", rd_val, 32'hFFFFFFFF);
        hr(21'h130000); expect_v("new BAR address decodes", rd_val, 32'h50434901);
        // a BAR value outside the 2 MiB window never decodes, whatever its low bits are
        cfg_wr(8'h00, 10'h04, 32'hFA130000, 4'hF);
        hr(21'h130000); expect_v("BAR0 outside the window", rd_val, 32'hFFFFFFFF);
        cfg_wr(8'h00, 10'h04, 32'hF9130000, 4'hF);
        // cache line size and interrupt line
        cfg_wr(8'h00, 10'h03, 32'h00000010, 4'h1); cfg_rd(8'h00, 10'h03); expect_v("cache line size", rd_val, 32'h00000010);
        cfg_wr(8'h00, 10'h0F, 32'h0000000B, 4'h1); cfg_rd(8'h00, 10'h0F); expect_v("interrupt line", rd_val, 32'h0000010B);
        // back-to-back pairs
        for (i = 0; i < 8; i = i + 1) begin
            hw(21'h130028 + i * 4, 32'hC0DE0000 + i, 4'hF);
            hr(21'h130028 + i * 4); expect_v("burst of mailbox words", rd_val, 32'hC0DE0000 + i);
        end
        // reset returns the configuration to its idle state
        @(negedge clk); rst_n = 1'b0; repeat (3) @(posedge clk); @(negedge clk); rst_n = 1'b1; repeat (3) @(posedge clk);
        cfg_rd(8'h00, 10'h01); expect_v("command after reset", rd_val, 32'h00000000);
        cfg_rd(8'h00, 10'h04); expect_v("BAR0 after reset", rd_val, 32'h00000000);
        cfg_rd(8'h00, 10'h0F); expect_v("interrupt line after reset", rd_val, 32'h00000100);

        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (errors == 0 && checks > 40) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin
        #3000000;
        $display("TBRESULT watchdog FAIL");
        $finish;
    end
endmodule
