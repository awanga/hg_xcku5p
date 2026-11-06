// SPDX-License-Identifier: MIT
// One register stage for the GMII receive inputs (RXD, RX_DV, RX_ER) in the PHY's RX clock domain. It gives each pad a single
// load so the placer can put the capture flop next to the pin; without it RX_DV fanned out into the MAC's preamble checker and the
// route alone took about 5 ns, more than the PHY's setup guarantee allows. All bits move together, so the MAC sees the same
// stream one RX clock later.
module gmii_rx_reg #(
    parameter W = 10
) (
    input  wire         clk,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);
    reg [W-1:0] r = {W{1'b0}};
    assign q = r;

    always @(posedge clk) r <= d;
endmodule
