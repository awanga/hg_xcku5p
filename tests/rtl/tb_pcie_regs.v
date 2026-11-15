// SPDX-License-Identifier: MIT
// pcie_regs: expected values are written out from the register map in the module header (not read back from the DUT).
// Two AXI4-Lite masters (host and CPU) in one clock; the PCIe user clock is modelled by a toggle input that is switched on and off.
`timescale 1ns / 1ps
module tb_pcie_regs;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [6:0]  h_awaddr = 7'd0, h_araddr = 7'd0, c_awaddr = 7'd0, c_araddr = 7'd0;
    reg  [31:0] h_wdata = 32'd0, c_wdata = 32'd0;
    reg         h_awvalid = 1'b0, h_wvalid = 1'b0, h_arvalid = 1'b0, h_bready = 1'b1, h_rready = 1'b1;
    reg         c_awvalid = 1'b0, c_wvalid = 1'b0, c_arvalid = 1'b0, c_bready = 1'b1, c_rready = 1'b1;
    wire        h_awready, h_wready, h_bvalid, h_arready, h_rvalid;
    wire        c_awready, c_wready, c_bvalid, c_arready, c_rvalid;
    wire [1:0]  h_bresp, h_rresp, c_bresp, c_rresp;
    wire [31:0] h_rdata, c_rdata;
    reg         link_up = 1'b0, perst_n = 1'b0, tog_en = 1'b0, tog = 1'b0;
    wire        irq, cpu_db_any;
    wire [31:0] win_base, win_size;

    pcie_regs dut (.clk(clk), .rst_n(rst_n),
        .h_awaddr(h_awaddr), .h_awvalid(h_awvalid), .h_awready(h_awready), .h_wdata(h_wdata), .h_wstrb(4'hF), .h_wvalid(h_wvalid),
        .h_wready(h_wready), .h_bresp(h_bresp), .h_bvalid(h_bvalid), .h_bready(h_bready), .h_araddr(h_araddr), .h_arvalid(h_arvalid),
        .h_arready(h_arready), .h_rdata(h_rdata), .h_rresp(h_rresp), .h_rvalid(h_rvalid), .h_rready(h_rready),
        .c_awaddr(c_awaddr), .c_awvalid(c_awvalid), .c_awready(c_awready), .c_wdata(c_wdata), .c_wstrb(4'hF), .c_wvalid(c_wvalid),
        .c_wready(c_wready), .c_bresp(c_bresp), .c_bvalid(c_bvalid), .c_bready(c_bready), .c_araddr(c_araddr), .c_arvalid(c_arvalid),
        .c_arready(c_arready), .c_rdata(c_rdata), .c_rresp(c_rresp), .c_rvalid(c_rvalid), .c_rready(c_rready),
        .link_up_a(link_up), .aclk_toggle_a(tog), .perst_n_a(perst_n), .win_base(win_base), .win_size(win_size), .irq(irq), .cpu_db_any(cpu_db_any));

    // PCIe user clock stand-in, 8 ns period when enabled, asynchronous to clk
    always #4 if (tog_en) tog = ~tog;

    integer errors = 0, checks = 0;
    reg [31:0] rd_val;

    // One driver process per port variable: the tasks below are the only writers of h_* / c_*.
    task h_write(input [6:0] a, input [31:0] d);
        begin
            @(negedge clk);
            h_awaddr = a; h_wdata = d; h_awvalid = 1'b1; h_wvalid = 1'b1;
            @(posedge clk); while (!(h_awready && h_wready)) @(posedge clk);
            @(negedge clk); h_awvalid = 1'b0; h_wvalid = 1'b0;
            @(posedge clk); while (!h_bvalid) @(posedge clk);
            if (h_bresp !== 2'b00) begin errors = errors + 1; $display("FAIL host bresp"); end
        end
    endtask
    task c_write(input [6:0] a, input [31:0] d);
        begin
            @(negedge clk);
            c_awaddr = a; c_wdata = d; c_awvalid = 1'b1; c_wvalid = 1'b1;
            @(posedge clk); while (!(c_awready && c_wready)) @(posedge clk);
            @(negedge clk); c_awvalid = 1'b0; c_wvalid = 1'b0;
            @(posedge clk); while (!c_bvalid) @(posedge clk);
            if (c_bresp !== 2'b00) begin errors = errors + 1; $display("FAIL cpu bresp"); end
        end
    endtask
    task h_read(input [6:0] a);
        begin
            @(negedge clk); h_araddr = a; h_arvalid = 1'b1;
            @(posedge clk); while (!h_arready) @(posedge clk);
            @(negedge clk); h_arvalid = 1'b0;
            @(posedge clk); while (!h_rvalid) @(posedge clk);
            #1 rd_val = h_rdata;
            if (h_rresp !== 2'b00) begin errors = errors + 1; $display("FAIL host rresp"); end
        end
    endtask
    task c_read(input [6:0] a);
        begin
            @(negedge clk); c_araddr = a; c_arvalid = 1'b1;
            @(posedge clk); while (!c_arready) @(posedge clk);
            @(negedge clk); c_arvalid = 1'b0;
            @(posedge clk); while (!c_rvalid) @(posedge clk);
            #1 rd_val = c_rdata;
            if (c_rresp !== 2'b00) begin errors = errors + 1; $display("FAIL cpu rresp"); end
        end
    endtask
    task expect_(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            checks = checks + 1;
            if (got !== want) begin errors = errors + 1; $display("FAIL %0s: got %h want %h", what, got, want); end
        end
    endtask

    integer i;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // identity and reset state
        h_read(7'h00); expect_("host ID", rd_val, 32'h50434901);
        c_read(7'h00); expect_("cpu ID", rd_val, 32'h50434901);
        c_read(7'h04); expect_("status at reset (no link, no clock, PERST# asserted)", rd_val, 32'h0);
        h_write(7'h00, 32'h0); h_read(7'h00); expect_("ID is read only", rd_val, 32'h50434901);

        // status inputs: PERST#, core clock activity, link
        perst_n = 1'b1; repeat (4) @(posedge clk);
        c_read(7'h04); expect_("status perst", rd_val, 32'h4);
        tog_en = 1'b1; repeat (8) @(posedge clk);
        c_read(7'h04); expect_("status clock alive", rd_val, 32'h6);
        link_up = 1'b1; repeat (4) @(posedge clk);
        c_read(7'h04); expect_("status link up, sticky set", rd_val, 32'h27);
        h_read(7'h04); expect_("host status", rd_val, 32'h27);
        link_up = 1'b0; repeat (4) @(posedge clk);
        c_read(7'h04); expect_("link down keeps ever_up", rd_val, 32'h26);
        c_write(7'h04, 32'h20); c_read(7'h04); expect_("cpu clears ever_up", rd_val, 32'h6);
        h_write(7'h04, 32'h20); link_up = 1'b1; repeat (4) @(posedge clk); link_up = 1'b0; repeat (4) @(posedge clk);
        h_write(7'h04, 32'h20); c_read(7'h04); expect_("host cannot clear ever_up", rd_val, 32'h26);
        c_write(7'h04, 32'h20);
        tog_en = 1'b0; repeat (20000) @(posedge clk);
        c_read(7'h04); expect_("clock stop is detected only after a long silence", rd_val, 32'h6);
        repeat (45700) @(posedge clk);
        c_read(7'h04); expect_("clock stopped", rd_val, 32'h4);

        // host -> CPU doorbell and interrupt
        h_write(7'h08, 32'h5);
        c_read(7'h08); expect_("cpu sees host db", rd_val, 32'h5);
        h_read(7'h08); expect_("host sees host db", rd_val, 32'h5);
        c_read(7'h04); expect_("status host db pending", rd_val, 32'h0c);
        expect_("irq masked by IEN", irq, 1'b0);
        h_write(7'h10, 32'h1); c_read(7'h10); expect_("IEN is CPU only", rd_val, 32'h0);
        c_write(7'h10, 32'h1); repeat (2) @(posedge clk);
        expect_("irq when enabled and pending", irq, 1'b1);
        c_write(7'h08, 32'h1); repeat (2) @(posedge clk);
        c_read(7'h08); expect_("W1C clears bit 0 only", rd_val, 32'h4);
        expect_("irq held while a bit is pending", irq, 1'b1);
        c_write(7'h08, 32'h4); repeat (2) @(posedge clk);
        expect_("irq drops when cleared", irq, 1'b0);
        h_write(7'h08, 32'h2); h_write(7'h08, 32'h8); c_read(7'h08); expect_("host W1S accumulates", rd_val, 32'ha);
        c_write(7'h08, 32'hffffffff);
        // a set and a clear of the same bit in the same cycle: the set must survive
        fork
            h_write(7'h08, 32'h80);
            c_write(7'h08, 32'h80);
        join
        c_read(7'h08); h_read(7'h08);
        expect_("same-cycle set and clear: the set survives", rd_val, 32'h80);
        c_write(7'h08, 32'hffffffff);

        // CPU -> host doorbell
        expect_("no cpu db yet", cpu_db_any, 1'b0);
        c_write(7'h0c, 32'h2);
        repeat (2) @(posedge clk);
        expect_("cpu db any", cpu_db_any, 1'b1);
        h_read(7'h0c); expect_("host sees cpu db", rd_val, 32'h2);
        c_read(7'h04); expect_("status cpu db pending", rd_val, 32'h14);
        c_write(7'h0c, 32'h4); h_read(7'h0c); expect_("cpu W1S accumulates", rd_val, 32'h6);
        h_write(7'h0c, 32'h2); h_read(7'h0c); expect_("host W1C clears bit 1", rd_val, 32'h4);
        c_write(7'h0c, 32'h0); h_read(7'h0c); expect_("write of 0 changes nothing", rd_val, 32'h4);
        h_write(7'h0c, 32'h4); repeat (2) @(posedge clk);
        expect_("cpu db cleared", cpu_db_any, 1'b0);

        // mailbox shared by both sides
        for (i = 0; i < 16; i = i + 1) h_write(7'h20 + 4 * i, 32'hA5000000 + i);
        for (i = 0; i < 16; i = i + 1) begin
            c_read(7'h20 + 4 * i); expect_("cpu reads host mailbox", rd_val, 32'hA5000000 + i);
        end
        c_write(7'h2c, 32'h12345678); h_read(7'h2c); expect_("host reads cpu mailbox write", rd_val, 32'h12345678);
        h_read(7'h28); expect_("neighbour unchanged", rd_val, 32'hA5000002);
        fork
            h_write(7'h40, 32'h11111111);
            c_write(7'h40, 32'h22222222);
        join
        h_read(7'h40); expect_("cpu wins a same-cycle mailbox write", rd_val, 32'h22222222);
        c_read(7'h60); expect_("unmapped reads 0", rd_val, 32'h0);

        // host access counters: writes so far counted by the host port only
        h_read(7'h14); i = rd_val;
        c_write(7'h20, 32'h1);
        h_write(7'h20, 32'h2);
        h_read(7'h14); expect_("host write counter +1 (cpu writes not counted)", rd_val, i + 1);
        h_read(7'h18); i = rd_val;
        c_read(7'h00); c_read(7'h00);
        h_read(7'h18); expect_("host read counter +1", rd_val, i + 1);

        // DMA window registers: CPU only
        expect_("window closed at reset", win_size, 32'h0);
        c_write(7'h70, 32'h7E00_0000); c_write(7'h74, 32'h0100_0000);
        expect_("window base output", win_base, 32'h7E00_0000);
        expect_("window size output", win_size, 32'h0100_0000);
        c_read(7'h70); expect_("cpu reads window base", rd_val, 32'h7E00_0000);
        c_read(7'h74); expect_("cpu reads window size", rd_val, 32'h0100_0000);
        h_write(7'h70, 32'h1111_1111); h_write(7'h74, 32'h2222_2222);
        expect_("host cannot change the window base", win_base, 32'h7E00_0000);
        expect_("host cannot change the window size", win_size, 32'h0100_0000);
        h_read(7'h74); expect_("host reads 0 for the window size", rd_val, 32'h0);
        h_read(7'h70); expect_("host reads 0 for the window base", rd_val, 32'h0);

        // reset clears doorbells, interrupt enable and counters
        h_write(7'h08, 32'h1); c_write(7'h0c, 32'h1);
        rst_n = 1'b0; repeat (3) @(posedge clk); rst_n = 1'b1; repeat (3) @(posedge clk);
        c_read(7'h08); expect_("reset clears host db", rd_val, 32'h0);
        c_read(7'h0c); expect_("reset clears cpu db", rd_val, 32'h0);
        c_read(7'h10); expect_("reset clears IEN", rd_val, 32'h0);
        c_read(7'h14); expect_("reset clears counter", rd_val, 32'h0);
        expect_("reset closes the window", win_size, 32'h0);

        $display("TBRESULT checks=%0d errors=%0d %s", checks, errors, (errors == 0 && checks > 60) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin #50000000; $display("TBRESULT timeout FAIL"); $finish; end
endmodule
