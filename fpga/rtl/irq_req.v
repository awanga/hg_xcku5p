// SPDX-License-Identifier: MIT
// One user-interrupt request toward the XDMA core (usr_irq_req / usr_irq_ack, axi_aclk). `lvl` is a level from another clock domain (synchronised here).
// Contract (the behaviour of the original doorbell logic in pcie_ep, unchanged): when lvl is seen high a request is raised and held until the core
// acknowledges it, or dropped if lvl falls first; after an ack no further request is made until lvl has gone low: one message per assertion. A handler must clear the cause and re-read the pending bits until none
// is left; a cause that arrives between its read and its clear keeps lvl high and raises no new message.
// `seen` is the synchronised level (valid whether or not the core is in reset, so it shows the connection up to this module even with no PCIe link;
// `req` needs the core out of reset, which the core only does with a link).
module irq_req (
    input  wire clk,
    input  wire rst_n,
    input  wire lvl,
    input  wire ack,
    output reg  req,
    output wire seen
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] s;
    reg acked;
    assign seen = s[1];
    always @(posedge clk) begin
        s <= {s[0], lvl};
        if (!rst_n) begin
            req <= 1'b0;
            acked <= 1'b0;
        end else begin
            if (!s[1]) begin
                req <= 1'b0;
                acked <= 1'b0;
            end else if (ack) begin
                req <= 1'b0;
                acked <= 1'b1;
            end else if (!acked) req <= 1'b1;
        end
    end
endmodule
