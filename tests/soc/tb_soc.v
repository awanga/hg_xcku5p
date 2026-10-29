// SPDX-License-Identifier: MIT
// System simulation of the generated VexiiRiscv SoC netlist running fw/boot from a ROM image.
//   - ROM / board registers / UART transmit model behind the AXI-Lite port (axil_simple, boot_rom, soc_regs)
//   - 256-bit AXI4 memory model with a fixed read latency standing in for the clock converter + DDR4 controller
// The console text is checked by tests/soc/run.sh against the firmware specification (banner, CPU kHz, calibration,
// "errors: 0" per pass, no mismatch line); this bench ends after PASSES error-free passes or on the watchdog.
`timescale 1ns / 1ps
module tb_soc;
    parameter ROM_INIT = "boot_rom.hex";
    parameter LAT = 20;
    parameter PASSES = 2;
    parameter integer MEM_WORDS = 1 << 21; // 64 MiB of 256-bit words, address wraps
    parameter integer CORRUPT = 0;         // fault injection: flip bit 0 of read data for beats at this index (0 = off)

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #1.25 clk = ~clk;

    wire        m_awvalid, m_wvalid, m_wlast, m_bready, m_arvalid, m_rready;
    reg         m_awready, m_wready, m_bvalid, m_arready, m_rvalid, m_rlast;
    wire [31:0] m_awaddr, m_araddr;
    wire [7:0]  m_awid, m_arid, m_awlen, m_arlen;
    reg  [7:0]  m_bid, m_rid;
    wire [2:0]  m_awsize, m_arsize;
    wire [1:0]  m_awburst, m_arburst;
    reg  [255:0] m_rdata;
    wire [255:0] m_wdata;
    wire [31:0] m_wstrb;

    wire        p_awvalid, p_wvalid, p_bready, p_arvalid, p_rready;
    wire        p_awready, p_wready, p_bvalid, p_arready, p_rvalid;
    wire [31:0] p_awaddr, p_araddr, p_wdata, p_rdata;
    wire [3:0]  p_wstrb;
    wire [1:0]  p_bresp, p_rresp;
    wire [2:0]  p_awprot, p_arprot;

    `SOC_MODULE u_soc (
        .litex_clk(clk), .litex_reset(rst), .peripheral_externalInterrupts_port(32'd0),
        .mBus_awvalid(m_awvalid), .mBus_awready(m_awready), .mBus_awaddr(m_awaddr), .mBus_awid(m_awid),
        .mBus_awlen(m_awlen), .mBus_awsize(m_awsize), .mBus_awburst(m_awburst), .mBus_awallStrb(),
        .mBus_wvalid(m_wvalid), .mBus_wready(m_wready), .mBus_wdata(m_wdata), .mBus_wstrb(m_wstrb), .mBus_wlast(m_wlast),
        .mBus_bvalid(m_bvalid), .mBus_bready(m_bready), .mBus_bid(m_bid), .mBus_bresp(2'b00),
        .mBus_arvalid(m_arvalid), .mBus_arready(m_arready), .mBus_araddr(m_araddr), .mBus_arid(m_arid),
        .mBus_arlen(m_arlen), .mBus_arsize(m_arsize), .mBus_arburst(m_arburst),
        .mBus_rvalid(m_rvalid), .mBus_rready(m_rready), .mBus_rdata(m_rdata), .mBus_rid(m_rid),
        .mBus_rresp(2'b00), .mBus_rlast(m_rlast),
        .pBus_awvalid(p_awvalid), .pBus_awready(p_awready), .pBus_awaddr(p_awaddr), .pBus_awprot(p_awprot),
        .pBus_wvalid(p_wvalid), .pBus_wready(p_wready), .pBus_wdata(p_wdata), .pBus_wstrb(p_wstrb),
        .pBus_bvalid(p_bvalid), .pBus_bready(p_bready), .pBus_bresp(p_bresp),
        .pBus_arvalid(p_arvalid), .pBus_arready(p_arready), .pBus_araddr(p_araddr), .pBus_arprot(p_arprot),
        .pBus_rvalid(p_rvalid), .pBus_rready(p_rready), .pBus_rdata(p_rdata), .pBus_rresp(p_rresp),
`ifdef WITH_DMA
        .dma_bus_awvalid(1'b0), .dma_bus_awready(), .dma_bus_awaddr(32'd0), .dma_bus_awid(4'd0),
        .dma_bus_awlen(8'd0), .dma_bus_awsize(3'd0), .dma_bus_awburst(2'd1),
        .dma_bus_wvalid(1'b0), .dma_bus_wready(), .dma_bus_wdata(256'd0), .dma_bus_wstrb(32'd0), .dma_bus_wlast(1'b0),
        .dma_bus_bvalid(), .dma_bus_bready(1'b1), .dma_bus_bid(), .dma_bus_bresp(),
        .dma_bus_arvalid(1'b0), .dma_bus_arready(), .dma_bus_araddr(32'd0), .dma_bus_arid(4'd0),
        .dma_bus_arlen(8'd0), .dma_bus_arsize(3'd0), .dma_bus_arburst(2'd1),
        .dma_bus_rvalid(), .dma_bus_rready(1'b1), .dma_bus_rdata(), .dma_bus_rid(),
        .dma_bus_rresp(), .dma_bus_rlast(),
`endif
        .debug());

    // ------------------------------------------------------------ peripherals
    wire [31:0] pa_addr, pa_wdata, pa_rdata;
    wire [3:0]  pa_wstrb;
    wire        pa_we, pa_re;
    assign p_bresp = 2'b00;
    assign p_rresp = 2'b00;
    axil_simple #(.AW(32)) u_if (
        .clk(clk), .rst_n(~rst),
        .s_awaddr(p_awaddr), .s_awvalid(p_awvalid), .s_awready(p_awready),
        .s_wdata(p_wdata), .s_wstrb(p_wstrb), .s_wvalid(p_wvalid), .s_wready(p_wready),
        .s_bresp(), .s_bvalid(p_bvalid), .s_bready(p_bready),
        .s_araddr(p_araddr), .s_arvalid(p_arvalid), .s_arready(p_arready),
        .s_rdata(p_rdata), .s_rresp(), .s_rvalid(p_rvalid), .s_rready(p_rready),
        .addr(pa_addr), .we(pa_we), .wdata(pa_wdata), .wstrb(pa_wstrb), .re(pa_re), .rdata(pa_rdata));

    wire sel_rom  = (pa_addr[31:16] == 16'h1000);
    wire sel_uart = (pa_addr[31:12] == 20'hF8000);
    wire sel_regs = (pa_addr[31:12] == 20'hF8001);
    reg  [1:0] rsel;
    wire [31:0] rom_rd, regs_rd;
    always @(posedge clk) if (pa_re) rsel <= {sel_regs, sel_rom};
    boot_rom #(.WORDS(4096), .AW(12), .INIT_FILE(ROM_INIT)) u_rom (
        .clk(clk), .en(pa_re && sel_rom), .addr(pa_addr[13:2]), .rdata(rom_rd));
    wire [7:0] led;
    soc_regs #(.CPU_KHZ(400000)) u_regs (
        .clk(clk), .rst_n(~rst), .we(pa_we && sel_regs), .addr(pa_addr[4:2]), .wdata(pa_wdata), .wstrb(pa_wstrb),
        .re(pa_re && sel_regs), .rdata(regs_rd), .led(led), .key_in(1'b0), .ddr_calib_in(1'b1), .ddr_rst_n_in(1'b1));
    assign pa_rdata = rsel[0] ? rom_rd : (rsel[1] ? regs_rd : 32'd0);

    // UART model: a TX register write prints the character; STAT reads as "never full" (0).
    // The last 11 characters are kept to count complete error-free passes ("errors: 0\r\n").
    reg [8*11-1:0] hist;
    integer passes = 0;
    always @(posedge clk) begin
        if (pa_we && sel_uart && pa_addr[3:2] == 2'd1) begin
            $write("%c", pa_wdata[7:0]);
            hist = {hist[8*10-1:0], pa_wdata[7:0]};
            if (hist == "errors: 0\r\n") passes = passes + 1;
        end
    end

    // ------------------------------------------------------------ AXI4 memory model
    reg [255:0] mem [0:MEM_WORDS-1];
    integer ii;
    initial for (ii = 0; ii < MEM_WORDS; ii = ii + 1) mem[ii] = 256'd0;

    localparam S_IDLE = 0, S_RLAT = 1, S_RDATA = 2, S_WDATA = 3, S_WRSP = 4;
    integer st = S_IDLE;
    integer lat_cnt;
    reg [31:0] cur_addr;
    reg [7:0]  cur_len, cur_id, beat;
    integer    rd_beats = 0;
    reg [255:0] wd;
    integer    k;

    initial begin
        m_awready = 1'b0; m_wready = 1'b0; m_bvalid = 1'b0; m_arready = 1'b0; m_rvalid = 1'b0; m_rlast = 1'b0;
        m_bid = 8'd0; m_rid = 8'd0; m_rdata = 256'd0;
    end

    always @(posedge clk) begin
        m_arready <= 1'b0;
        m_awready <= 1'b0;
        m_wready  <= 1'b0;
        case (st)
        S_IDLE: begin
            if (m_arvalid && !m_arready) begin
                m_arready <= 1'b1;
                cur_addr <= m_araddr; cur_len <= m_arlen; cur_id <= m_arid; beat <= 8'd0;
                lat_cnt <= LAT;
                st <= S_RLAT;
            end else if (m_awvalid && !m_awready) begin
                m_awready <= 1'b1;
                cur_addr <= m_awaddr; cur_len <= m_awlen; cur_id <= m_awid; beat <= 8'd0;
                st <= S_WDATA;
            end
        end
        S_RLAT: begin
            if (lat_cnt == 0) begin
                m_rvalid <= 1'b1; m_rid <= cur_id;
                m_rdata <= mem[(cur_addr[26:5]) & (MEM_WORDS - 1)];
                if (CORRUPT != 0 && rd_beats == CORRUPT) m_rdata <= mem[(cur_addr[26:5]) & (MEM_WORDS - 1)] ^ 256'd1;
                rd_beats = rd_beats + 1;
                m_rlast <= (cur_len == 8'd0);
                st <= S_RDATA;
            end else lat_cnt <= lat_cnt - 1;
        end
        S_RDATA: begin
            if (m_rvalid && m_rready) begin
                if (beat == cur_len) begin
                    m_rvalid <= 1'b0; m_rlast <= 1'b0;
                    st <= S_IDLE;
                end else begin
                    beat <= beat + 1'b1;
                    cur_addr <= cur_addr + 32'd32;
                    m_rdata <= mem[((cur_addr + 32'd32) >> 5) & (MEM_WORDS - 1)];
                    rd_beats = rd_beats + 1;
                    m_rlast <= (beat + 1'b1 == cur_len);
                end
            end
        end
        S_WDATA: begin
            m_wready <= 1'b1;
            if (m_wvalid && m_wready) begin
                wd = mem[(cur_addr >> 5) & (MEM_WORDS - 1)];
                for (k = 0; k < 32; k = k + 1)
                    if (m_wstrb[k]) wd[8*k +: 8] = m_wdata[8*k +: 8];
                mem[(cur_addr >> 5) & (MEM_WORDS - 1)] <= wd;
                cur_addr <= cur_addr + 32'd32;
                if (m_wlast) begin
                    m_wready <= 1'b0;
                    m_bvalid <= 1'b1; m_bid <= cur_id;
                    st <= S_WRSP;
                end
            end
        end
        S_WRSP: begin
            if (m_bvalid && m_bready) begin
                m_bvalid <= 1'b0;
                st <= S_IDLE;
            end
        end
        default: st <= S_IDLE;
        endcase
    end

    // ------------------------------------------------------------ run control
    integer cycles = 0;
    initial begin
        repeat (20) @(posedge clk);
        rst = 1'b0;
    end
    always @(posedge clk) cycles <= cycles + 1;

    initial begin
        wait (passes >= PASSES);
        repeat (50) @(posedge clk);
        $display("\nTBRESULT passes=%0d cycles=%0d PASS", passes, cycles);
        $finish;
    end
    initial begin
        #200000000;
        $display("\nTBRESULT passes=%0d cycles=%0d FAIL (watchdog)", passes, cycles);
        $finish;
    end
endmodule
