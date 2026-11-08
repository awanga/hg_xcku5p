// SPDX-License-Identifier: MIT
// DDR4 capacity test aid: extends the 1 GiB CPU memory address to the 31-bit address of an 8 Gb-per-chip controller (2 GiB).
// Address bit 30 is 0 except when sel is set and the access is in the top 256 MiB of the CPU window (addr[29:28] == 2'b11):
// then the window shows the upper 1 GiB half at the same CPU addresses. Everything below 0x70000000 is never remapped, so code and
// stack stay put while the test flips sel. sel is quasi-static: change it only while no access to the top 256 MiB is in flight.
module ddr_halfmap (
    input  wire [29:0] addr,
    input  wire        sel,
    output wire [30:0] ddr_addr
);
    assign ddr_addr = {sel & (addr[29:28] == 2'b11), addr};
endmodule
