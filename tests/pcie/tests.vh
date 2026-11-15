// SPDX-License-Identifier: MIT
// Included inside the vendor root-port test (usp_pci_exp_usrapp_tx.v) in place of its tests.vh: the vendor's own tests stay available and
// two tests of the HG-XCKU5P endpoint are added. Select with +TESTNAME=pcie_ep_regs or +TESTNAME=pcie_ep_dma. Expected values come from the
// register map in fpga/rtl/pcie_regs.v and from the DMA window contract in fpga/rtl/axi_win.v, not from the design's behaviour.
`include "sample_tests.vh"
else if (testname == "pcie_ep_regs") begin : t_regs
    integer errs;
    integer n;
    begin
        errs = 0;
        board.EP.find_lite_bar;
        $display("[%t] pcie_ep_regs: XDMA BAR %0d, host register BAR %0d", $realtime, board.RP.tx_usrapp.xdma_bar, board.EP.lite_bar);
        if (board.EP.lite_bar < 0) begin errs = errs + 1; $display("ERROR: no AXI-Lite BAR enabled"); end

        // identity and link status, read by the host over PCIe (BAR0 -> XDMA AXI-Lite master -> clock converter -> pcie_regs)
        board.EP.host_rd(32'h00);
        if (board.EP.host_rdata !== 32'h50434901) begin errs = errs + 1; $display("ERROR: ID %h != 50434901", board.EP.host_rdata); end
        board.EP.host_rd(32'h04);
        // bit0 link up, bit1 core clock, bit2 PERST# released, bit5 link was up
        if (board.EP.host_rdata !== 32'h27) begin errs = errs + 1; $display("ERROR: status %h != 27", board.EP.host_rdata); end
        // the same registers seen by the CPU window
        board.EP.cpu_read(7'h04);
        if (board.EP.cpu_rdata !== 32'h27) begin errs = errs + 1; $display("ERROR: cpu status %h != 27", board.EP.cpu_rdata); end

        // mailbox: host writes, CPU reads; CPU writes, host reads
        board.EP.host_wr(32'h28, 32'hCAFE0001);
        board.EP.cpu_read(7'h28);
        if (board.EP.cpu_rdata !== 32'hCAFE0001) begin errs = errs + 1; $display("ERROR: cpu mailbox %h", board.EP.cpu_rdata); end
        board.EP.cpu_write(7'h2C, 32'h0BADF00D);
        board.EP.host_rd(32'h2C);
        if (board.EP.host_rdata !== 32'h0BADF00D) begin errs = errs + 1; $display("ERROR: host mailbox %h", board.EP.host_rdata); end

        // host -> CPU doorbell and interrupt
        board.EP.cpu_write(7'h10, 32'h1);                 // IEN
        if (board.EP.irq !== 1'b0) begin errs = errs + 1; $display("ERROR: irq before doorbell"); end
        board.EP.host_wr(32'h08, 32'h2);
        n = 0;
        while (board.EP.irq !== 1'b1 && n < 200) begin #10000; n = n + 1; end
        if (board.EP.irq !== 1'b1) begin errs = errs + 1; $display("ERROR: no irq after host doorbell"); end
        board.EP.cpu_read(7'h08);
        if (board.EP.cpu_rdata !== 32'h2) begin errs = errs + 1; $display("ERROR: HOST_DB %h", board.EP.cpu_rdata); end
        board.EP.cpu_write(7'h08, 32'h2);                 // CPU clears it
        #100000;
        if (board.EP.irq !== 1'b0) begin errs = errs + 1; $display("ERROR: irq held after clear"); end

        // CPU -> host doorbell: user interrupt 0 is requested and acknowledged by the core, and the request is released
        // enable user interrupt 0 in the XDMA interrupt block (vector map at 0x2080, user interrupt enable mask at 0x2004)
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h2080, 32'h00000000, 4'hF);
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h2004, 32'h00000001, 4'hF);
        board.EP.cpu_write(7'h0C, 32'h1);
        n = 0;
        while (board.EP.u_ep.usr_irq_req[0] !== 1'b1 && n < 400) begin #10000; n = n + 1; end
        if (board.EP.u_ep.usr_irq_req[0] !== 1'b1) begin errs = errs + 1; $display("ERROR: no user interrupt request"); end
        n = 0;
        while (board.EP.u_ep.acked !== 1'b1 && n < 4000) begin #10000; n = n + 1; end
        if (board.EP.u_ep.acked !== 1'b1) begin errs = errs + 1; $display("ERROR: user interrupt not acknowledged"); end
        board.EP.host_rd(32'h0C);
        if (board.EP.host_rdata !== 32'h1) begin errs = errs + 1; $display("ERROR: CPU_DB seen by host %h", board.EP.host_rdata); end
        board.EP.host_wr(32'h0C, 32'h1);                  // host acknowledges
        n = 0;
        while (board.EP.u_ep.acked !== 1'b0 && n < 400) begin #10000; n = n + 1; end
        if (board.EP.u_ep.usr_irq_req[0] !== 1'b0 || board.EP.u_ep.acked !== 1'b0) begin errs = errs + 1; $display("ERROR: user interrupt not released"); end

        // the write counter counts register writes by the host only: this test issued three (mailbox, HOST_DB, CPU_DB); the CPU's writes and the
        // XDMA register writes (a different BAR) are not counted
        board.EP.cpu_read(7'h14);
        if (board.EP.cpu_rdata !== 32'd3) begin errs = errs + 1; $display("ERROR: host write count %0d != 3", board.EP.cpu_rdata); end

        if (errs == 0) $display("[%t] pcie_ep_regs: Test Completed Successfully", $realtime);
        else $display("[%t] pcie_ep_regs: TEST FAILED, %0d errors", $realtime, errs);
        #1000;
        $finish;
    end
end
else if (testname == "pcie_ep_dma") begin : t_dma
    integer errs;
    integer k;
    integer loop_to;
    integer aw0;
    reg [31:0] st;
    begin
        errs = 0;
        board.EP.find_lite_bar;
        // the memory behind the endpoint holds its sentinel
        for (k = 0; k < 64; k = k + 1) if (board.EP.mem[k] !== 8'hEE) errs = errs + 1;

        // 1. window closed (reset state): a host-programmed DMA must be refused and must not reach the memory
        aw0 = board.EP.aw_count;
        board.RP.tx_usrapp.TSK_INIT_DATA_H2C;
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h4080, 32'h00000100, 4'hF);
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00fffe7f, 4'hF);
        loop_to = 0;
        st = 32'd0;
        while (loop_to < 20 && st[31:1] === 31'd0) begin
            #100000;
            board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h0040);
            st = board.RP.tx_usrapp.P_READ_DATA;
            loop_to = loop_to + 1;
        end
        $display("[%t] H2C status with the window closed: %h", $realtime, st);
        if (st === 32'h6) begin errs = errs + 1; $display("ERROR: DMA completed although the window is closed"); end
        if (board.EP.aw_count !== aw0) begin errs = errs + 1; $display("ERROR: write reached the memory port with the window closed"); end
        for (k = 0; k < 16; k = k + 1) if (board.EP.mem[k] !== 8'hEE) begin errs = errs + 1; $display("ERROR: memory byte %0d changed", k); end
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00000000, 4'hF);   // stop the engine, clear its status
        board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h0044);

        // 2. window opened by the CPU: host-to-card DMA lands in the memory, then card-to-host returns it
        board.EP.cpu_write(7'h70, 32'h0000_0000);
        board.EP.cpu_write(7'h74, 32'h0001_0000);
        #200000;
        board.RP.tx_usrapp.TSK_INIT_DATA_H2C;
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h4080, 32'h00000100, 4'hF);
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00fffe7f, 4'hF);
        loop_to = 0;
        st = 32'd0;
        while (loop_to < 20 && st !== 32'h6) begin
            #100000;
            board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h0040);
            st = board.RP.tx_usrapp.P_READ_DATA;
            loop_to = loop_to + 1;
        end
        if (st !== 32'h6) begin errs = errs + 1; $display("ERROR: H2C status %h != 6", st); end
        for (k = 0; k < 16; k = k + 1) if (board.EP.mem[k] !== k[7:0]) begin errs = errs + 1; $display("ERROR: mem[%0d] = %h", k, board.EP.mem[k]); end
        if (board.EP.mem[16] !== 8'hEE) begin errs = errs + 1; $display("ERROR: write ran past the 16 bytes"); end
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00000000, 4'hF);

        board.RP.tx_usrapp.TSK_INIT_DATA_C2H;
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h5080, 32'h00000300, 4'hF);
        fork
            board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h1004, 32'h00fffe7f, 4'hF);
            board.RP.tx_usrapp.COMPARE_DATA_C2H({16'h0, board.RP.tx_usrapp.DMA_BYTE_CNT});
        join
        loop_to = 0;
        st = 32'd0;
        while (loop_to < 20 && st !== 32'h6) begin
            #100000;
            board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h1040);
            st = board.RP.tx_usrapp.P_READ_DATA;
            loop_to = loop_to + 1;
        end
        if (st !== 32'h6) begin errs = errs + 1; $display("ERROR: C2H status %h != 6", st); end

        // 3. a CPU-closed window is enforced again
        board.EP.cpu_write(7'h74, 32'h0);
        #200000;
        aw0 = board.EP.aw_count;
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00000000, 4'hF);
        board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h0044);
        board.RP.tx_usrapp.TSK_INIT_DATA_H2C;
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h4080, 32'h00000100, 4'hF);
        board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00fffe7f, 4'hF);
        #2000000;
        if (board.EP.aw_count !== aw0) begin errs = errs + 1; $display("ERROR: write reached the memory after the window was closed again"); end

        if (errs == 0) $display("[%t] pcie_ep_dma: Test Completed Successfully", $realtime);
        else $display("[%t] pcie_ep_dma: TEST FAILED, %0d errors", $realtime, errs);
        #1000;
        $finish;
    end
end
