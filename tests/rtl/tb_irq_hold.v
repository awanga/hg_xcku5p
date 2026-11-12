// SPDX-License-Identifier: MIT
// System-level check of the UART interrupt path: behavioural models of the AMD UART Lite receive interrupt (one pulse when the RX FIFO
// becomes non-empty, re-armed by an RX read, as in axi_uartlite_v2_0_rfs.vhd), the PLIC gateway (samples its source only while not waiting
// for completion, as in the generated TilelinkPlic) and an interrupt handler that loops on status/receive like Linux's ulite_isr.
// Expected: every byte that arrives is received and the FIFO is empty a bounded time after the last arrival.
`timescale 1ns / 1ps
module tb_irq_hold;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    // ---- UART receive FIFO model
    integer fifo_cnt = 0;
    reg     pre = 1'b0, uart_irq = 1'b0, rx_pop = 1'b0;
    wire    present = fifo_cnt > 0;
    reg arrive = 1'b0;
    integer received = 0;
    always @(posedge clk) begin
        pre <= rx_pop ? 1'b0 : present;
        uart_irq <= present & ~pre;
        fifo_cnt <= fifo_cnt + (arrive ? 1 : 0) - (rx_pop ? 1 : 0);
        if (rx_pop) received <= received + 1;
    end
    // ---- hold under test
    reg  stat_rd = 1'b0;
    wire level;
    irq_hold dut (.clk(clk), .rst_n(rst_n), .pulse(uart_irq), .clr(stat_rd | rx_pop), .level(level));
    // ---- PLIC gateway model
    reg gw_ip = 1'b0, gw_wait = 1'b0, claim = 1'b0, complete = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) begin gw_ip <= 1'b0; gw_wait <= 1'b0; end
        else begin
            if (!gw_wait) begin gw_ip <= level; gw_wait <= level; end
            if (claim) gw_ip <= 1'b0;
            if (complete) gw_wait <= 1'b0;
        end
    end
    // ---- handler model: claim, loop { read status; if data: read it }, complete
    integer st = 0, dly = 0, sent = 0, spurious = 0, isr_runs = 0;
    reg seen_data;
    always @(posedge clk) begin
        claim <= 1'b0; complete <= 1'b0; stat_rd <= 1'b0; rx_pop <= 1'b0;
        if (rst_n) begin
            if (dly > 0) dly <= dly - 1;
            else case (st)
            0: if (gw_ip) begin claim <= 1'b1; isr_runs <= isr_runs + 1; seen_data = 1'b0; st <= 1; dly <= 3 + ($random & 15); end
            1: begin stat_rd <= 1'b1; st <= 2; dly <= 2; end
            2: if (present) begin rx_pop <= 1'b1; seen_data = 1'b1; st <= 1; dly <= 4; end
               else begin if (!seen_data) spurious <= spurious + 1; st <= 3; dly <= 4 + ($random & 15); end
            3: begin complete <= 1'b1; st <= 0; dly <= 1; end
            endcase
        end
    end
    // ---- byte arrivals: random gaps (some shorter than one handler run, some long)
    integer gap = 0, n = 0, runtime = 0;
    parameter NBYTES = 3000;
    always @(posedge clk) begin
        arrive <= 1'b0;
        if (rst_n && n < NBYTES) begin
            if (gap > 0) gap <= gap - 1;
            else begin
                arrive <= 1'b1;
                n <= n + 1; sent <= sent + 1;
                gap <= 8 + (($random & 32'h7fffffff) % 120);
            end
        end
    end
    integer errors = 0, checks = 0;
    initial begin
        #100 rst_n = 1'b1;
        wait (n == NBYTES);
        repeat (3000) @(posedge clk);
        checks = checks + 1;
        if (received !== sent || fifo_cnt !== 0) begin
            errors = errors + 1;
            $display("FAIL sent=%0d received=%0d fifo left=%0d runs=%0d", sent, received, fifo_cnt, isr_runs);
        end
        checks = checks + 1;
        if (spurious > sent) begin errors = errors + 1; $display("FAIL interrupt storm: %0d empty runs", spurious); end
        $display("handler runs=%0d empty runs=%0d", isr_runs, spurious);
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
    initial begin #400000000 $display("TBRESULT watchdog FAIL"); $finish; end
endmodule
