// SPDX-License-Identifier: MIT
// Maps the AXI GPIO bits (one 19-bit channel) to the board pins. Purely combinational.
//   bit 0      DS18B20 data (the open-drain IOBUF stays in soc_top; its input is ds18b20_i)
//   bit 1      buzzer, active high (output only; reads back the pin level)
//   bit 2      fan tach input
//   bits 3-10  LED0-LED7, active high; an LED lights only when its direction bit is output (t = 0) and data = 1,
//              so the power-up default (all inputs, t = 1) leaves every LED off. Reads back the pin level.
//   bits 11-14 KEY_PL0-KEY_PL3 (pushbuttons, active high, no debounce), inputs
//   bits 15-18 SW1-SW4 (DIP switches, polarity as wired), inputs
module board_gpio_map (
    // Bits 0 (IOBUF in soc_top), 2 and 11-18 (inputs) have no output side here.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [18:0] gpio_o,
    input  wire [18:0] gpio_t,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire        ds18b20_i,
    input  wire        fan_fb,
    input  wire [3:0]  key,
    input  wire [3:0]  sw,
    output wire [18:0] gpio_i,
    output wire        beep,
    output wire [7:0]  led
);
    assign beep = gpio_o[1] & ~gpio_t[1];
    assign led = gpio_o[10:3] & ~gpio_t[10:3];
    assign gpio_i = {sw, key, led, fan_fb, beep, ds18b20_i};
endmodule
