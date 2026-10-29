// SPDX-License-Identifier: MIT
// AXI-Lite master drives soc_regs and boot_rom through axil_simple. Expected values come from the register map
// in soc_regs.v and from the ROM image written by tests/rtl/gen_rom.py (word i = (i * 2654435761) ^ A5A5A5A5).
`timescale 1ns / 1ps
module tb_soc_periph;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // register slave
    reg  [15:0] r_awaddr, r_araddr;
    reg         r_awvalid, r_wvalid, r_arvalid, r_bready, r_rready;
    reg  [31:0] r_wdata;
    reg  [3:0]  r_wstrb;
    wire        r_awready, r_wready, r_bvalid, r_arready, r_rvalid;
    wire [31:0] r_rdata;
    wire [15:0] r_addr;
    wire        r_we, r_re;
    wire [31:0] r_wd, r_rd;
    wire [3:0]  r_ws;
    wire [7:0]  led;
    reg         key = 1'b0, calib = 1'b0, drst = 1'b0;

    axil_simple #(.AW(16)) u_if_r (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(r_awaddr), .s_awvalid(r_awvalid), .s_awready(r_awready),
        .s_wdata(r_wdata), .s_wstrb(r_wstrb), .s_wvalid(r_wvalid), .s_wready(r_wready),
        .s_bresp(), .s_bvalid(r_bvalid), .s_bready(r_bready),
        .s_araddr(r_araddr), .s_arvalid(r_arvalid), .s_arready(r_arready),
        .s_rdata(r_rdata), .s_rresp(), .s_rvalid(r_rvalid), .s_rready(r_rready),
        .addr(r_addr), .we(r_we), .wdata(r_wd), .wstrb(r_ws), .re(r_re), .rdata(r_rd));
    soc_regs #(.CPU_KHZ(400000)) u_regs (
        .clk(clk), .rst_n(rst_n), .we(r_we), .addr(r_addr[4:2]), .wdata(r_wd), .wstrb(r_ws),
        .re(r_re), .rdata(r_rd), .led(led), .key_in(key), .ddr_calib_in(calib), .ddr_rst_n_in(drst));

    // rom slave
    reg  [15:0] m_araddr;
    reg         m_arvalid, m_rready;
    wire        m_arready, m_rvalid;
    wire [31:0] m_rdata;
    wire [15:0] m_addr;
    wire        m_re;
    wire [31:0] m_rd;
    axil_simple #(.AW(16)) u_if_m (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(16'd0), .s_awvalid(1'b0), .s_awready(),
        .s_wdata(32'd0), .s_wstrb(4'd0), .s_wvalid(1'b0), .s_wready(),
        .s_bresp(), .s_bvalid(), .s_bready(1'b1),
        .s_araddr(m_araddr), .s_arvalid(m_arvalid), .s_arready(m_arready),
        .s_rdata(m_rdata), .s_rresp(), .s_rvalid(m_rvalid), .s_rready(m_rready),
        .addr(m_addr), .we(), .wdata(), .wstrb(), .re(m_re), .rdata(m_rd));
    boot_rom #(.WORDS(64), .AW(6), .INIT_FILE("rom_test.hex")) u_rom (
        .clk(clk), .en(m_re), .addr(m_addr[7:2]), .rdata(m_rd));

    integer checks = 0;
    integer errors = 0;
    integer guard;

    task expect32(input [31:0] got, input [31:0] want, input [255:0] what);
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                $display("MISMATCH %0s: got %h want %h", what, got, want);
            end
        end
    endtask

    task reg_write(input [15:0] a, input [31:0] d, input [3:0] s, input aw_first);
        begin
            @(negedge clk);
            if (aw_first) begin r_awaddr = a; r_awvalid = 1'b1; end
            else begin r_wdata = d; r_wstrb = s; r_wvalid = 1'b1; end
            repeat (3) @(negedge clk);
            r_awaddr = a; r_awvalid = 1'b1; r_wdata = d; r_wstrb = s; r_wvalid = 1'b1;
            guard = 0;
            while (!(r_awready && r_wready) && guard < 50) begin @(negedge clk); guard = guard + 1; end
            @(negedge clk);
            r_awvalid = 1'b0; r_wvalid = 1'b0; r_bready = 1'b0;
            guard = 0;
            while (!r_bvalid && guard < 50) begin @(negedge clk); guard = guard + 1; end
            repeat (2) @(negedge clk);
            if (!r_bvalid) begin errors = errors + 1; $display("BVALID dropped before BREADY"); end
            r_bready = 1'b1; @(negedge clk); r_bready = 1'b0;
            if (guard >= 50) begin errors = errors + 1; $display("write timeout"); end
        end
    endtask

    task reg_read(input [15:0] a, output [31:0] d);
        begin
            @(negedge clk);
            r_araddr = a; r_arvalid = 1'b1;
            guard = 0;
            while (!r_arready && guard < 50) begin @(negedge clk); guard = guard + 1; end
            @(negedge clk); r_arvalid = 1'b0;
            guard = 0;
            while (!r_rvalid && guard < 50) begin @(negedge clk); guard = guard + 1; end
            repeat (2) @(negedge clk);
            if (!r_rvalid) begin errors = errors + 1; $display("RVALID dropped before RREADY"); end
            d = r_rdata;
            r_rready = 1'b1; @(negedge clk); r_rready = 1'b0;
            if (guard >= 50) begin errors = errors + 1; $display("read timeout"); end
        end
    endtask

    task rom_read(input [15:0] a, output [31:0] d);
        begin
            @(negedge clk);
            m_araddr = a; m_arvalid = 1'b1;
            guard = 0;
            while (!m_arready && guard < 50) begin @(negedge clk); guard = guard + 1; end
            @(negedge clk); m_arvalid = 1'b0;
            while (!m_rvalid && guard < 50) begin @(negedge clk); guard = guard + 1; end
            d = m_rdata;
            m_rready = 1'b1; @(negedge clk); m_rready = 1'b0;
        end
    endtask

    reg [31:0] v;
    reg [31:0] t0, t1;
    integer i;
    initial begin
        r_awvalid = 0; r_wvalid = 0; r_arvalid = 0; r_bready = 0; r_rready = 0;
        r_awaddr = 0; r_araddr = 0; r_wdata = 0; r_wstrb = 0;
        m_araddr = 0; m_arvalid = 0; m_rready = 0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        reg_read(16'h000, v); expect32(v, 32'h0, "LED reset");
        reg_write(16'h000, 32'hFFFFFFA5, 4'b0001, 1'b1);
        expect32({24'd0, led}, 32'hA5, "LED out");
        reg_read(16'h000, v); expect32(v, 32'hA5, "LED readback");
        reg_write(16'h000, 32'h000000FF, 4'b0010, 1'b0); // strobe excludes byte 0
        expect32({24'd0, led}, 32'hA5, "LED strobe ignored");

        reg_read(16'h004, v); expect32(v, 32'h0, "KEY released");
        key = 1'b1; repeat (4) @(negedge clk);
        reg_read(16'h004, v); expect32(v, 32'h1, "KEY pressed");
        reg_read(16'h008, v); expect32(v, 32'h0, "STATUS idle");
        calib = 1'b1; repeat (4) @(negedge clk);
        reg_read(16'h008, v); expect32(v, 32'h1, "STATUS calib only");
        drst = 1'b1; repeat (4) @(negedge clk);
        reg_read(16'h008, v); expect32(v, 32'h3, "STATUS calib+rst");
        reg_read(16'h00C, v); expect32(v, 32'd400000, "CPU_KHZ");
        reg_read(16'h010, t0); reg_read(16'h010, t1);
        checks = checks + 1;
        if (!(t1 > t0)) begin errors = errors + 1; $display("TICK not increasing %0d %0d", t0, t1); end

        reg_write(16'h014, 32'h12345678, 4'b1111, 1'b0);
        reg_read(16'h014, v); expect32(v, 32'h12345678, "SCRATCH");
        reg_write(16'h014, 32'hAABBCCDD, 4'b0101, 1'b1);
        reg_read(16'h014, v); expect32(v, 32'h12BB56DD, "SCRATCH byte strobes");
        reg_read(16'h018, v); expect32(v, 32'h0, "unmapped reads 0");

        for (i = 0; i < 64; i = i + 1) begin
            rom_read(i * 4, v);
            expect32(v, ((i * 32'h9E3779B1) ^ 32'hA5A5A5A5), "ROM word");
        end
        rom_read(16'h0FC, v); // wraps within the 64-word array: addr[7:2] = 63
        expect32(v, ((63 * 32'h9E3779B1) ^ 32'hA5A5A5A5), "ROM last word");

        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("TBRESULT checks=%0d errors=%0d FAIL (watchdog)", checks, errors + 1);
        $finish;
    end
endmodule
