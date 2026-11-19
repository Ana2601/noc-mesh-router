// 5-port wormhole router for a 2-D mesh network-on-chip.
//
//  * Ports: 0 Local, 1 North (+y), 2 East (+x), 3 South (-y), 4 West (-x)
//  * Input-buffered (one FWFT FIFO per input), valid/ready link flow control
//  * Deterministic XY dimension-order routing (deadlock-free on a mesh)
//  * Per-output round-robin arbitration; an output is locked to the winning
//    input from head flit to tail flit (wormhole switching), so packets never
//    interleave on a link
//  * Single-cycle hop: a flit at the head of an input FIFO can be written into
//    the downstream FIFO on the next clock edge
//
// Flit = {type[1:0], data[DATA_W-1:0]}
//   type: 2'b10 head, 2'b00 body, 2'b01 tail, 2'b11 head+tail (single-flit packet)
//   head data: [XW-1:0] destination x, [XW+YW-1:XW] destination y, rest is payload
module noc_router #(
    parameter integer DATA_W = 32,
    parameter integer XW     = 4,
    parameter integer YW     = 4,
    parameter integer DEPTH  = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [XW-1:0]           my_x,
    input  wire [YW-1:0]           my_y,

    input  wire [4:0]              in_valid,
    output wire [4:0]              in_ready,
    input  wire [5*(DATA_W+2)-1:0] in_flit,

    output wire [4:0]              out_valid,
    input  wire [4:0]              out_ready,
    output wire [5*(DATA_W+2)-1:0] out_flit
);
    localparam integer FW = DATA_W + 2;
    localparam [2:0] P_L = 3'd0, P_N = 3'd1, P_E = 3'd2, P_S = 3'd3, P_W = 3'd4;

    // ------------------------------------------------------------ input buffers
    wire [FW-1:0] q_flit  [0:4];
    wire [4:0]    q_empty, q_full;
    wire [4:0]    q_pop;
    wire [4:0]    q_head;
    wire [2:0]    q_route [0:4];

    genvar i, o;
    generate
        for (i = 0; i < 5; i = i + 1) begin : g_in
            noc_fifo #(.W(FW), .DEPTH(DEPTH)) u_fifo (
                .clk(clk), .rst_n(rst_n),
                .push(in_valid[i] && in_ready[i]), .din(in_flit[i*FW +: FW]), .full(q_full[i]),
                .pop(q_pop[i]), .dout(q_flit[i]), .empty(q_empty[i])
            );
            assign in_ready[i] = !q_full[i];
            assign q_head[i]   = q_flit[i][FW-1];

            // XY route computation on the head flit
            wire [XW-1:0] dx = q_flit[i][XW-1:0];
            wire [YW-1:0] dy = q_flit[i][XW+YW-1:XW];
            assign q_route[i] = (dx > my_x) ? P_E :
                                (dx < my_x) ? P_W :
                                (dy > my_y) ? P_N :
                                (dy < my_y) ? P_S : P_L;
        end
    endgenerate

    // ------------------------------------------------------------ switch allocation
    reg  [4:0] busy;              // output is mid-packet
    reg  [2:0] owner [0:4];       // input that owns each output
    reg  [2:0] rr    [0:4];       // round-robin pointer (last granted input)
    wire [4:0] xfer;              // flit transferred on output o this cycle
    wire [2:0] sel   [0:4];       // input currently driving output o
    wire [4:0] pop_by_out [0:4];  // one-hot over inputs, per output

    generate
        for (o = 0; o < 5; o = o + 1) begin : g_out
            // inputs with a head flit that wants this output
            wire [4:0] req;
            for (i = 0; i < 5; i = i + 1) begin : g_req
                assign req[i] = !q_empty[i] && q_head[i] && (q_route[i] == o);
            end

            // round-robin: first requester after rr[o]
            reg [2:0] gnt;
            reg       gnt_v;
            integer k;
            reg [3:0] idx;      // one bit wider than a port index so rr+k cannot wrap
            always @* begin
                gnt = 3'd0; gnt_v = 1'b0; idx = 4'd0;
                // scan rr+5 down to rr+1 so the closest requester after rr wins
                for (k = 5; k >= 1; k = k - 1) begin
                    idx = {1'b0, rr[o]} + k[3:0];
                    if (idx >= 4'd5) idx = idx - 4'd5;
                    if (req[idx[2:0]]) begin gnt = idx[2:0]; gnt_v = 1'b1; end
                end
            end

            assign sel[o]       = busy[o] ? owner[o] : gnt;
            wire   src_valid    = busy[o] ? !q_empty[owner[o]] : gnt_v;
            assign out_valid[o] = src_valid;
            assign out_flit[o*FW +: FW] = q_flit[sel[o]];
            assign xfer[o]      = src_valid && out_ready[o];
            assign pop_by_out[o] = xfer[o] ? (5'd1 << sel[o]) : 5'd0;

            wire is_tail = q_flit[sel[o]][FW-2];
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    busy[o]  <= 1'b0;
                    owner[o] <= 3'd0;
                    rr[o]    <= 3'd4;
                end else if (xfer[o]) begin
                    if (!busy[o]) begin
                        owner[o] <= gnt;
                        rr[o]    <= gnt;
                        busy[o]  <= !is_tail;      // single-flit packets never lock
                    end else if (is_tail) begin
                        busy[o]  <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    assign q_pop = pop_by_out[0] | pop_by_out[1] | pop_by_out[2] | pop_by_out[3] | pop_by_out[4];
endmodule
