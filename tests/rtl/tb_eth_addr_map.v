// SPDX-License-Identifier: MIT
// Expected addresses come from the address plan (CPU window 0xF8008000, core CSRs 0xF8020000, core buffers 0xF8030000), not the RTL.
`timescale 1ns / 1ps
module tb_eth_addr_map;
    reg  [31:0] cpu = 0;
    wire [31:0] core;
    eth_addr_map dut (.cpu_addr(cpu), .core_addr(core));
    integer errors = 0, checks = 0;
    task t(input [31:0] c, input [31:0] want);
        begin
            cpu = c; #1; checks = checks + 1;
            if (core !== want) begin errors = errors + 1; $display("FAIL cpu=%08h core=%08h want=%08h", c, core, want); end
        end
    endtask
    initial begin
        t(32'hF8008000, 32'hF8020000); // CSR bank 0 (ctrl)
        t(32'hF8008800, 32'hF8020800); // ethphy bank
        t(32'hF8009000, 32'hF8021000); // ethmac bank
        t(32'hF8009040, 32'hF8021040); // crc_errors
        t(32'hF800BFFC, 32'hF8023FFC); // last CSR word of the first half
        t(32'hF800C000, 32'hF8030000); // RX buffer slot 0
        t(32'hF800C800, 32'hF8030800); // RX buffer slot 1
        t(32'hF800D000, 32'hF8031000); // TX buffer slot 0
        t(32'hF800DFFC, 32'hF8031FFC); // last TX buffer word
        t(32'hF800FFFC, 32'hF8033FFC); // last word of the window
        if (checks > 0 && errors == 0) $display("TBRESULT checks=%0d errors=%0d PASS", checks, errors);
        else $display("TBRESULT checks=%0d errors=%0d FAIL", checks, errors);
        $finish;
    end
endmodule
