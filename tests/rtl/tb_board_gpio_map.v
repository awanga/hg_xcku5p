// SPDX-License-Identifier: MIT
// Expected values come from the bit map in the header of board_gpio_map.v, evaluated bit by bit.
`timescale 1ns / 1ps
module tb_board_gpio_map;
    reg  [18:0] o = 19'd0, t = 19'h7FFFF;
    reg         ds = 1'b0, fb = 1'b0;
    reg  [3:0]  key = 4'd0, sw = 4'd0;
    wire [18:0] gi;
    wire        beep;
    wire [7:0]  led;
    board_gpio_map dut (.gpio_o(o), .gpio_t(t), .ds18b20_i(ds), .fan_fb(fb), .key(key), .sw(sw),
                        .gpio_i(gi), .beep(beep), .led(led));
    integer errors = 0, checks = 0, i, k;
    reg [18:0] want_i;
    reg        want_beep;
    reg [7:0]  want_led;
    task check;
        begin
            #1;
            want_beep = (t[1] == 1'b0) && (o[1] == 1'b1);
            for (k = 0; k < 8; k = k + 1) want_led[k] = (t[3 + k] == 1'b0) && (o[3 + k] == 1'b1);
            want_i[0] = ds;
            want_i[1] = want_beep;
            want_i[2] = fb;
            for (k = 0; k < 8; k = k + 1) want_i[3 + k] = want_led[k];
            for (k = 0; k < 4; k = k + 1) want_i[11 + k] = key[k];
            for (k = 0; k < 4; k = k + 1) want_i[15 + k] = sw[k];
            checks = checks + 1;
            if (gi !== want_i || beep !== want_beep || led !== want_led) begin
                errors = errors + 1;
                $display("FAIL o=%h t=%h ds=%b fb=%b key=%h sw=%h: gi=%h/%h beep=%b/%b led=%h/%h", o, t, ds, fb, key, sw, gi, want_i, beep, want_beep, led, want_led);
            end
        end
    endtask
    initial begin
        // power-up default: every pin an input, nothing lit, nothing buzzing
        check;
        if (led !== 8'h00 || beep !== 1'b0) begin errors = errors + 1; $display("FAIL default state not quiet"); end
        // one pin at a time, as output driven high, then as input with data high
        for (i = 0; i < 19; i = i + 1) begin
            o = 19'd1 << i; t = ~(19'd1 << i); check;
            o = 19'd1 << i; t = 19'h7FFFF; check;
            o = ~(19'd1 << i); t = ~(19'd1 << i); check;
        end
        // every input combination on the pad side
        for (i = 0; i < 1024; i = i + 1) begin
            {sw, key, fb, ds} = i[9:0];
            o = i * 19'd377; t = (i * 19'd1009) ^ 19'h2AAAA; check;
        end
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
