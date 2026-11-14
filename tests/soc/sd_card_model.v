// SPDX-License-Identifier: MIT
// Behavioural SD card in SPI mode (mode 0), enough for fw/boot/sd.c: CMD0, CMD8, CMD55/ACMD41 (ready on the 3rd try), CMD58 (SDHC),
// CMD16, CMD18 (multi-block read) and CMD12. Card contents come from a $readmemh byte file (one hex byte per line).
// Written from the SD Physical Layer SPI-mode description, not from the driver.
`timescale 1ns / 1ps
module sd_card_model #(
    parameter IMAGE = "sd.hex",
    parameter integer BYTES = 65536
) (
    input  wire sck,
    input  wire mosi,
    output reg  miso,
    input  wire cs_n
);
    reg [7:0] img [0:BYTES-1];
    integer i;
    initial begin
        for (i = 0; i < BYTES; i = i + 1) img[i] = 8'h00;
        $readmemh(IMAGE, img);
        miso = 1'b1;
    end

    // byte receiver
    reg [7:0]  rx = 8'hFF;
    integer    bitn = 0;
    // command assembly
    integer    cmd_idx = 0;
    reg [47:0] cmd = 48'd0;
    integer    acmd_tries = 0;
    reg        app_cmd = 1'b0;
    // transmit queue (byte level)
    reg [7:0]  txq [0:4095];
    integer    txq_n = 0, txq_r = 0;
    reg [7:0]  tx_cur = 8'hFF;
    integer    tx_bit = 0;
    // multi-block read state
    reg        reading = 1'b0;
    integer    rd_addr = 0;
    integer    blk_pos = 0;     // 0..515: gap, token, data, crc
    reg        idle_state = 1'b1;
    reg        skip_fall = 1'b0;

    task push(input [7:0] b);
        begin txq[txq_n % 4096] = b; txq_n = txq_n + 1; end
    endtask

    task handle_cmd;
        reg [5:0] c;
        reg [31:0] arg;
        begin
            c = cmd[45:40];
            arg = cmd[39:8];
            reading = 1'b0;
            txq_n = 0; txq_r = 0;
            case (c)
            6'd0:  begin idle_state = 1'b1; acmd_tries = 0; push(8'h01); end
            6'd8:  begin push(8'h01); push(8'h00); push(8'h00); push(arg[15:8]); push(arg[7:0]); end
            6'd55: begin app_cmd = 1'b1; push(idle_state ? 8'h01 : 8'h00); end
            6'd41: begin
                if (app_cmd) begin
                    acmd_tries = acmd_tries + 1;
                    if (acmd_tries >= 3) idle_state = 1'b0;
                    push(idle_state ? 8'h01 : 8'h00);
                end else push(8'h05);
            end
            6'd58: begin push(8'h00); push(8'hC0); push(8'hFF); push(8'h80); push(8'h00); end
            6'd16: push(8'h00);
            6'd18: begin
                push(8'h00);
                reading = 1'b1; rd_addr = arg * 512; blk_pos = 0;
            end
            6'd12: begin push(8'hFF); push(8'h00); push(8'h00); push(8'h00); end
            default: push(8'h04);
            endcase
            if (c != 6'd55) app_cmd = 1'b0;
        end
    endtask

    // next byte the card shifts out when the host clocks the next byte
    task next_tx_byte;
        begin
            if (txq_r < txq_n) begin
                tx_cur = txq[txq_r % 4096];
                txq_r = txq_r + 1;
            end else if (reading) begin
                if (blk_pos == 0) tx_cur = 8'hFF;
                else if (blk_pos == 1) tx_cur = 8'hFE;
                else if (blk_pos < 514) begin
                    tx_cur = img[(rd_addr + blk_pos - 2) % BYTES];
                end else tx_cur = 8'h00; // CRC
                blk_pos = blk_pos + 1;
                if (blk_pos == 516) begin blk_pos = 0; rd_addr = rd_addr + 512; end
            end else tx_cur = 8'hFF;
            tx_bit = 0;
            skip_fall = 1'b1; // the falling edge that ends this host byte must not advance the new byte
            miso = tx_cur[7];
        end
    endtask

    always @(negedge cs_n) begin
        bitn = 0; cmd_idx = 0; tx_bit = 0; miso = 1'b1; skip_fall = 1'b0;
    end
    always @(posedge sck) if (!cs_n) begin
        rx = {rx[6:0], mosi};
        bitn = bitn + 1;
        if (bitn == 8) begin
            bitn = 0;
            // host byte complete: assemble commands (start byte 01xxxxxx), ignore stray 0xFF fill
            if (cmd_idx == 0) begin
                if (rx[7:6] == 2'b01) begin cmd = {rx, 40'd0}; cmd_idx = 1; end
            end else begin
                cmd = cmd | ({40'd0, rx} << (8 * (5 - cmd_idx)));
                cmd_idx = cmd_idx + 1;
                if (cmd_idx == 6) begin cmd_idx = 0; handle_cmd; end
            end
            next_tx_byte;
        end
    end
    always @(negedge sck) if (!cs_n) begin
        if (skip_fall) skip_fall = 1'b0;
        else begin
            tx_bit = tx_bit + 1;
            if (tx_bit < 8) miso = tx_cur[7 - tx_bit];
        end
    end
endmodule
