// SPDX-License-Identifier: MIT
// 10:1 TMDS serializer, two bits per clk5 cycle (ODDRE1), LSB first. clk5 is 5x the pixel clock from the same MMCM. The 10-bit word `word` is
// registered in the pixel domain together with a toggle `tg`; this block loads it into the shift register in the clk5 cycle after the toggle has been seen,
// so a load happens exactly every 5 clk5 cycles and the word is stable (it only changes with the next pixel clock edge, 5 cycles later).
// Latency from the pixel-clock edge that changes `word` to the first bit on `q`: 3-4 clk5 cycles, constant. Reset: none (the output is a free-running
// pattern while the clocks run).
module tmds_ser (
    input  wire       clk5,
    input  wire       tg,
    input  wire [9:0] word,
    output wire       q
);
    reg       tg1 = 1'b0, tg2 = 1'b0;
    reg [9:0] sh = 10'd0;
    always @(posedge clk5) begin
        tg1 <= tg;
        tg2 <= tg1;
        if (tg1 ^ tg2) sh <= word;
        else sh <= {2'b00, sh[9:2]};
    end
    ODDRE1 u_oddr (.C(clk5), .D1(sh[0]), .D2(sh[1]), .SR(1'b0), .Q(q));
endmodule
