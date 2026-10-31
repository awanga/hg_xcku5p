// SPDX-License-Identifier: MIT
// Address window of the LiteEth core. The CPU reaches only 0xF8000000-0xF800FFFF, but the generated core decodes its CSRs
// at 0xF8020000 and its packet buffers at 0xF8030000. The crossbar sends the 32 KiB window at 0xF8008000 here:
//   window offset 0x0000-0x3FFF -> 0xF8020000 + offset (CSRs)       offset 0x4000-0x7FFF -> 0xF8030000 + (offset - 0x4000) (buffers)
module eth_addr_map (
    // verilator lint_off UNUSEDSIGNAL
    input  wire [31:0] cpu_addr,   // bits 31:15 are decoded by the crossbar
    // verilator lint_on UNUSEDSIGNAL
    output wire [31:0] core_addr
);
    assign core_addr = {15'b1111_1000_0000_001, cpu_addr[14], 2'b00, cpu_addr[13:0]};
endmodule
