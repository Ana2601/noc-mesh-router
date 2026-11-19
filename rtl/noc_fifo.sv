// Small synchronous FIFO with first-word fall-through, used as a router input buffer.
module noc_fifo #(
    parameter integer W     = 34,
    parameter integer DEPTH = 4          // power of two
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         push,
    input  wire [W-1:0] din,
    output wire         full,
    input  wire         pop,
    output wire [W-1:0] dout,
    output wire         empty
);
    localparam integer AW = $clog2(DEPTH);
    reg [W-1:0] mem [0:DEPTH-1];
    reg [AW:0]  wp, rp;

    assign empty = (wp == rp);
    assign full  = (wp[AW] != rp[AW]) && (wp[AW-1:0] == rp[AW-1:0]);
    assign dout  = mem[rp[AW-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp <= {(AW+1){1'b0}};
            rp <= {(AW+1){1'b0}};
        end else begin
            if (push && !full) begin
                mem[wp[AW-1:0]] <= din;
                wp <= wp + 1'b1;
            end
            if (pop && !empty) rp <= rp + 1'b1;
        end
    end
endmodule
