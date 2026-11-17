// SPDX-License-Identifier: MIT
// UART test rig for the CPU-less variant (decision 0008, variant 3): a line-based command interpreter that is the only bus master when no PC drives the
// card. Lines end in LF (CR is ignored); numbers are 1-8 hex digits, either case; the command letter may be either case.
//   W aaaaaaaa dddddddd   write one 32-bit word          -> OK        (ERR on a bus error)
//   R aaaaaaaa            read one 32-bit word           -> dddddddd  (ERR on a bus error)
//   B aaaaaaaa nnnn       read nnnn (1..FFFF) words at consecutive addresses, one line each; stops with ERR at the first bus error
//   I                     the interrupt input vector     -> dddddddd
//   V                     identification                 -> HGRIG1
// A malformed line (unknown command, wrong argument count, a non-hex character, more than 8 digits, an unaligned address, zero count) -> ERR.
// Addresses 0x40000000-0x7FFFFFFF go to the memory port (AXI4, 256-bit, one single-beat access per word, byte lane chosen by address bits 4:2);
// every other address goes to the peripheral port (AXI4-Lite, 32-bit). One command runs at a time; bytes that arrive before the response is complete are
// dropped (the host waits for the reply). A transaction the slave never answers stalls the rig until reset.
module uart_rig #(
    parameter CLKS_PER_BIT = 1447
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rx,
    output wire         tx,
    input  wire [31:0]  irq_in,
    // peripheral port (AXI4-Lite master)
    output wire [31:0]  p_awaddr,
    output wire [2:0]   p_awprot,
    output wire         p_awvalid,
    input  wire         p_awready,
    output wire [31:0]  p_wdata,
    output wire [3:0]   p_wstrb,
    output wire         p_wvalid,
    input  wire         p_wready,
    input  wire [1:0]   p_bresp,
    input  wire         p_bvalid,
    output wire         p_bready,
    output wire [31:0]  p_araddr,
    output wire [2:0]   p_arprot,
    output wire         p_arvalid,
    input  wire         p_arready,
    input  wire [31:0]  p_rdata,
    input  wire [1:0]   p_rresp,
    input  wire         p_rvalid,
    output wire         p_rready,
    // memory port (AXI4 master, 256-bit)
    output wire [31:0]  m_awaddr,
    output wire [7:0]   m_awlen,
    output wire [2:0]   m_awsize,
    output wire [1:0]   m_awburst,
    output wire         m_awvalid,
    input  wire         m_awready,
    output wire [255:0] m_wdata,
    output wire [31:0]  m_wstrb,
    output wire         m_wlast,
    output wire         m_wvalid,
    input  wire         m_wready,
    input  wire [1:0]   m_bresp,
    input  wire         m_bvalid,
    output wire         m_bready,
    output wire [31:0]  m_araddr,
    output wire [7:0]   m_arlen,
    output wire [2:0]   m_arsize,
    output wire [1:0]   m_arburst,
    output wire         m_arvalid,
    input  wire         m_arready,
    input  wire [255:0] m_rdata,
    input  wire [1:0]   m_rresp,
    input  wire         m_rvalid,
    output wire         m_rready
);
    // ---------------------------------------------------------------- serial
    wire [7:0] rxd;
    wire       rxv, rx_ferr;   // a frame with a bad stop bit is dropped silently; ferr is left unconnected on purpose
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk(clk), .rst_n(rst_n), .rx(rx), .data(rxd), .valid(rxv), .ferr(rx_ferr));
    /* verilator lint_off UNUSEDSIGNAL */
    wire       unused_ferr = rx_ferr;
    /* verilator lint_on UNUSEDSIGNAL */
    reg  [7:0] txd;
    reg        txv;
    wire       txr;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (.clk(clk), .rst_n(rst_n), .data(txd), .valid(txv), .ready(txr), .tx(tx));

    // ---------------------------------------------------------------- line parser
    reg [7:0]  cmd;
    reg [31:0] a0, a1, acc;
    reg [3:0]  nd;
    reg [1:0]  na;
    reg        bad;
    reg        busy;
    reg        go;

    function [3:0] hexval(input [7:0] c);
        hexval = (c >= "0" && c <= "9") ? c[3:0] : (c[3:0] + 4'd9);
    endfunction
    function is_hex(input [7:0] c);
        is_hex = (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F");
    endfunction
    function [7:0] hexchar(input [3:0] v);
        hexchar = (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h37 + {4'd0, v});
    endfunction

    // an argument ends at white space or at the end of the line
    wire       push = (nd != 4'd0);
    wire [31:0] acc_n = {acc[27:0], hexval(rxd)};

    // ---------------------------------------------------------------- executor
    localparam [3:0] X_IDLE = 4'd0, X_W = 4'd1, X_WB = 4'd2, X_R = 4'd3, X_RD = 4'd4, X_SEND = 4'd5, X_NEXT = 4'd6;
    reg [3:0]  xs;
    reg [31:0] addr, wd, cnt;
    reg        selm, burst, last;
    reg        aw_p, w_p, ar_p, aw_m, w_m, ar_m;
    reg [71:0] ob;
    reg [3:0]  on;

    assign p_awaddr = addr;
    assign p_awprot = 3'd0;
    assign p_awvalid = aw_p;
    assign p_wdata = wd;
    assign p_wstrb = 4'hF;
    assign p_wvalid = w_p;
    assign p_bready = (xs == X_WB) && !selm;
    assign p_araddr = addr;
    assign p_arprot = 3'd0;
    assign p_arvalid = ar_p;
    assign p_rready = (xs == X_RD) && !selm;

    assign m_awaddr = addr;
    assign m_awlen = 8'd0;
    assign m_awsize = 3'd2;
    assign m_awburst = 2'b01;
    assign m_awvalid = aw_m;
    assign m_wdata = {8{wd}};
    assign m_wstrb = 32'h0000000F << {addr[4:2], 2'b00};
    assign m_wlast = 1'b1;
    assign m_wvalid = w_m;
    assign m_bready = (xs == X_WB) && selm;
    assign m_araddr = addr;
    assign m_arlen = 8'd0;
    assign m_arsize = 3'd2;
    assign m_arburst = 2'b01;
    assign m_arvalid = ar_m;
    assign m_rready = (xs == X_RD) && selm;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] addr_n = addr + 32'd4;
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_off UNUSEDSIGNAL */
    wire [255:0] m_shift = m_rdata >> {addr[4:2], 5'd0};
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] m_word = m_shift[31:0];

    task load_hex(input [31:0] v);
        begin
            ob <= {hexchar(v[31:28]), hexchar(v[27:24]), hexchar(v[23:20]), hexchar(v[19:16]),
                   hexchar(v[15:12]), hexchar(v[11:8]), hexchar(v[7:4]), hexchar(v[3:0]), 8'h0A};
            on <= 4'd9;
        end
    endtask

    task send_err;
        begin
            ob <= {"ERR", 8'h0A, 40'd0};
            on <= 4'd4;
            last <= 1'b1;
            xs <= X_SEND;
        end
    endtask

    always @(posedge clk) begin
        txv <= 1'b0;
        if (!rst_n) begin
            cmd <= 8'd0; nd <= 4'd0; na <= 2'd0; bad <= 1'b0; acc <= 32'd0; busy <= 1'b0; go <= 1'b0;
            xs <= X_IDLE;
            aw_p <= 1'b0; w_p <= 1'b0; ar_p <= 1'b0; aw_m <= 1'b0; w_m <= 1'b0; ar_m <= 1'b0;
            on <= 4'd0;
        end else begin
            // ---------------- parser
            if (rxv && !busy) begin
                if (rxd == 8'h0D) begin
                end else if (rxd == 8'h0A) begin
                    if (cmd == 8'd0 && nd == 4'd0 && na == 2'd0 && !bad) begin
                        // empty line: nothing to do
                    end else begin
                        if (push) begin
                            if (na == 2'd0) a0 <= acc; else if (na == 2'd1) a1 <= acc; else bad <= 1'b1;
                            na <= na + 1'b1;
                        end
                        go <= 1'b1;
                        busy <= 1'b1;
                    end
                end else if (rxd == " " || rxd == 8'h09) begin
                    if (push) begin
                        if (na == 2'd0) a0 <= acc; else if (na == 2'd1) a1 <= acc; else bad <= 1'b1;
                        na <= na + 1'b1;
                        nd <= 4'd0;
                        acc <= 32'd0;
                    end
                end else if (cmd == 8'd0) begin
                    cmd <= (rxd >= "a" && rxd <= "z") ? rxd - 8'h20 : rxd;
                end else if (is_hex(rxd) && nd < 4'd8) begin
                    acc <= acc_n;
                    nd <= nd + 1'b1;
                end else bad <= 1'b1;
            end

            // ---------------- executor
            case (xs)
            X_IDLE: if (go) begin
                go <= 1'b0;
                addr <= a0;
                wd <= a1;
                cnt <= a1;
                burst <= 1'b0;
                selm <= (a0[31:30] == 2'b01);
                if (bad) begin
                    send_err;
                end else case (cmd)
                "W": if (na == 2'd2 && a0[1:0] == 2'b00) begin
                    xs <= X_W;
                    if (a0[31:30] == 2'b01) begin aw_m <= 1'b1; w_m <= 1'b1; end else begin aw_p <= 1'b1; w_p <= 1'b1; end
                end else send_err;
                "R": if (na == 2'd1 && a0[1:0] == 2'b00) begin
                    xs <= X_R;
                    if (a0[31:30] == 2'b01) ar_m <= 1'b1; else ar_p <= 1'b1;
                end else send_err;
                "B": if (na == 2'd2 && a0[1:0] == 2'b00 && a1 != 32'd0 && a1 <= 32'hFFFF) begin
                    burst <= 1'b1;
                    xs <= X_R;
                    if (a0[31:30] == 2'b01) ar_m <= 1'b1; else ar_p <= 1'b1;
                end else send_err;
                "I": if (na == 2'd0) begin load_hex(irq_in); xs <= X_SEND; last <= 1'b1; end
                    else send_err;
                "V": if (na == 2'd0) begin ob <= {"HGRIG1", 8'h0A, 16'd0}; on <= 4'd7; xs <= X_SEND; last <= 1'b1; end
                    else send_err;
                default: send_err;
                endcase
            end
            X_W: begin
                if (aw_p && p_awready) aw_p <= 1'b0;
                if (w_p && p_wready) w_p <= 1'b0;
                if (aw_m && m_awready) aw_m <= 1'b0;
                if (w_m && m_wready) w_m <= 1'b0;
                if ((!aw_p || p_awready) && (!w_p || p_wready) && (!aw_m || m_awready) && (!w_m || m_wready)) xs <= X_WB;
            end
            X_WB: if (selm ? m_bvalid : p_bvalid) begin
                if (selm ? (m_bresp != 2'b00) : (p_bresp != 2'b00)) send_err;
                else begin
                    ob <= {"OK", 8'h0A, 48'd0};
                    on <= 4'd3;
                    last <= 1'b1;
                    xs <= X_SEND;
                end
            end
            X_R: begin
                if (ar_p && p_arready) ar_p <= 1'b0;
                if (ar_m && m_arready) ar_m <= 1'b0;
                if ((!ar_p || p_arready) && (!ar_m || m_arready)) xs <= X_RD;
            end
            X_RD: if (selm ? m_rvalid : p_rvalid) begin
                if (selm ? (m_rresp != 2'b00) : (p_rresp != 2'b00)) send_err;
                else begin
                    load_hex(selm ? m_word : p_rdata);
                    last <= !burst || (cnt == 32'd1);
                    xs <= X_SEND;
                end
            end
            X_SEND: if (on != 4'd0) begin
                if (txr && !txv) begin
                    txd <= ob[71:64];
                    txv <= 1'b1;
                    ob <= {ob[63:0], 8'd0};
                    on <= on - 1'b1;
                end
            end else if (txr && !txv) begin
                if (last) begin
                    cmd <= 8'd0; nd <= 4'd0; na <= 2'd0; bad <= 1'b0; acc <= 32'd0; busy <= 1'b0;
                    xs <= X_IDLE;
                end else xs <= X_NEXT;
            end
            X_NEXT: begin
                addr <= addr + 32'd4;
                cnt <= cnt - 1'b1;
                selm <= (addr_n[31:30] == 2'b01);
                ar_m <= (addr_n[31:30] == 2'b01);
                ar_p <= (addr_n[31:30] != 2'b01);
                xs <= X_R;
            end
            default: xs <= X_IDLE;
            endcase
        end
    end
endmodule
