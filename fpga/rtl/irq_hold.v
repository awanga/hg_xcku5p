// SPDX-License-Identifier: MIT
// Turns the AMD UART Lite interrupt, a one-cycle pulse per event (RX FIFO becoming non-empty, TX FIFO becoming empty), into a level
// that stays up until the CPU reads the UART's status or receive register. The PLIC gateway samples a level source only while no
// earlier interrupt of that source is awaiting completion; a pulse that arrives inside that window (a byte received just after the
// handler's last status read) was lost, the byte stayed in the FIFO, and the console input hung until a later TX event ran the
// handler again. Held until the next read, the interrupt is seen again as soon as the gateway re-arms at "complete".
// Contract: set wins over clear in the same cycle; level rises one cycle after the pulse; reset value 0.
module irq_hold (
    input  wire clk,
    input  wire rst_n,
    input  wire pulse,
    input  wire clr,
    output reg  level
);
    always @(posedge clk) begin
        if (!rst_n) level <= 1'b0;
        else if (pulse) level <= 1'b1;
        else if (clr) level <= 1'b0;
    end
endmodule
