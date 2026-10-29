// SPDX-License-Identifier: MIT
// Word ROM with registered read (rdata valid 1 cycle after en). Initialised from a $readmemh file.
module boot_rom #(
    parameter WORDS = 4096,
    parameter AW = 12,
    parameter INIT_FILE = "boot_rom.hex"
) (
    input  wire          clk,
    input  wire          en,
    input  wire [AW-1:0] addr,
    output reg  [31:0]   rdata
);
    reg [31:0] mem [0:WORDS-1];
    initial $readmemh(INIT_FILE, mem);
    always @(posedge clk)
        if (en) rdata <= mem[addr];
endmodule
