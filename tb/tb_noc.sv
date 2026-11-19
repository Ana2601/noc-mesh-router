`timescale 1ns/1ps
// 4x4 mesh traffic testbench.
//  * every node injects random-length packets to uniformly random destinations
//  * every sink applies random back-pressure
//  * scoreboard checks: correct destination, per-flow in-order delivery, no
//    packet interleaving, payload integrity, nothing lost or duplicated
//  * reports average / max packet latency and accepted throughput
module tb_noc;
    localparam integer NX = 4, NY = 4, N = NX * NY, DW = 32, FW = DW + 2;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [N-1:0]    in_valid, in_ready, out_valid, out_ready;
    wire [N*FW-1:0] in_flit, out_flit;

    noc_mesh #(.NX(NX), .NY(NY), .DATA_W(DW), .DEPTH(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(in_valid), .loc_in_ready(in_ready), .loc_in_flit(in_flit),
        .loc_out_valid(out_valid), .loc_out_ready(out_ready), .loc_out_flit(out_flit)
    );

    // shared scoreboard state
    integer rate_pct = 10, sink_stall_pct = 10, run_cycles = 20000;
    reg     inject_en = 0;
    integer cyc = 0;
    integer sent_pkts = 0, recv_pkts = 0, sent_flits = 0, recv_flits = 0, errors = 0;
    longint lat_sum = 0;
    integer lat_max = 0;
    integer ts [0:N*N-1][0:255];     // head-injection time per (src,dst) flow and sequence number

    always @(posedge clk) cyc <= cyc + 1;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_node
            localparam integer MX = g % NX, MY = g / NX;

            // ---------------------------------------------------------- source
            reg          v = 0;
            reg [FW-1:0] f = 0;
            integer      len = 0, idx = 0, dst = 0, seq = 0;
            integer      next_seq [0:N-1];
            integer      j;
            assign in_valid[g]         = v;
            assign in_flit[g*FW +: FW] = f;

            initial for (j = 0; j < N; j = j + 1) next_seq[j] = 0;

            function automatic [FW-1:0] mk_flit(input integer i_idx, input integer i_len,
                                                 input integer i_dst, input integer i_seq);
                reg [1:0]  t;
                reg [31:0] d;
                begin
                    t = {i_idx == 0, i_idx == i_len - 1};
                    if (i_idx == 0)
                        d = {i_len[3:0], i_seq[11:0], MY[3:0], MX[3:0], 4'(i_dst / NX), 4'(i_dst % NX)};
                    else
                        d = {8'(g), i_seq[11:0], i_idx[3:0], 8'hA5 ^ 8'(i_idx * 37 + i_seq)};
                    mk_flit = {t, d};
                end
            endfunction

            always @(posedge clk) begin
                if (!rst_n) begin
                    v <= 0;
                end else if (v && in_ready[g]) begin
                    sent_flits = sent_flits + 1;
                    if (idx == len - 1) begin
                        v <= 0;
                        sent_pkts = sent_pkts + 1;
                    end else begin
                        idx <= idx + 1;
                        f   <= mk_flit(idx + 1, len, dst, seq);
                    end
                end else if (!v && inject_en && ($urandom_range(0, 999) < rate_pct * 10 / 4)) begin
                    // average packet is ~4 flits, so scale packet probability to hit the flit rate
                    dst = $urandom_range(0, N - 2);
                    if (dst >= g) dst = dst + 1;
                    len = $urandom_range(1, 7);
                    seq = next_seq[dst];
                    next_seq[dst] = (next_seq[dst] + 1) & 4095;
                    ts[g*N + dst][seq & 255] = cyc;
                    idx <= 0;
                    f   <= mk_flit(0, len, dst, seq);
                    v   <= 1;
                end
            end

            // ---------------------------------------------------------- sink
            reg          rdy = 0;
            integer      exp_seq [0:N-1];
            integer      r_src = 0, r_seq = 0, r_len = 0, r_idx = 0;
            reg          in_pkt = 0;
            wire [FW-1:0] of = out_flit[g*FW +: FW];
            wire [31:0]   od = of[31:0];
            assign out_ready[g] = rdy;

            initial for (j = 0; j < N; j = j + 1) exp_seq[j] = 0;

            task automatic bad(input string msg);
                begin
                    errors = errors + 1;
                    if (errors <= 20) $display("ERROR node %0d @%0d: %s (flit %h)", g, cyc, msg, of);
                end
            endtask

            always @(posedge clk) begin
                rdy <= ($urandom_range(0, 99) >= sink_stall_pct);
                if (rst_n && out_valid[g] && rdy) begin
                    recv_flits = recv_flits + 1;
                    if (of[FW-1]) begin                       // head
                        if (in_pkt) bad("head while a packet is open (interleaving)");
                        if (od[3:0] != MX || od[7:4] != MY) bad("misrouted packet");
                        r_src = od[11:8] + NX * od[15:12];
                        r_seq = od[27:16];
                        r_len = od[31:28];
                        r_idx = 0;
                        if (r_seq != exp_seq[r_src]) bad("out-of-order / lost packet");
                        exp_seq[r_src] = (r_seq + 1) & 4095;
                        in_pkt = 1;
                    end else begin
                        r_idx = r_idx + 1;
                        if (!in_pkt) bad("body flit with no open packet");
                        if (od[31:24] != r_src[7:0] || od[23:12] != r_seq[11:0] || od[11:8] != r_idx[3:0]
                            || od[7:0] != (8'hA5 ^ 8'(r_idx * 37 + r_seq)))
                            bad("payload corrupted");
                    end
                    if (of[FW-2]) begin                       // tail
                        if (r_idx != r_len - 1) bad("wrong packet length");
                        in_pkt = 0;
                        recv_pkts = recv_pkts + 1;
                        lat_sum = lat_sum + (cyc - ts[r_src*N + g][r_seq & 255]);
                        if (cyc - ts[r_src*N + g][r_seq & 255] > lat_max)
                            lat_max = cyc - ts[r_src*N + g][r_seq & 255];
                    end
                end
            end
        end
    endgenerate

    integer drain;
    initial begin
        void'($value$plusargs("rate=%d", rate_pct));
        void'($value$plusargs("stall=%d", sink_stall_pct));
        void'($value$plusargs("cycles=%d", run_cycles));
        repeat (5) @(posedge clk);
        rst_n = 1;
        inject_en = 1;
        repeat (run_cycles) @(posedge clk);
        inject_en = 0;
        // drain: stop when everything sent has arrived (or give up => deadlock/loss)
        drain = 0;
        while ((recv_pkts != sent_pkts || in_valid != 0) && drain < 20000) begin
            @(posedge clk);
            drain = drain + 1;
        end
        repeat (20) @(posedge clk);

        $display("NoC 4x4  offered=%0d%% flits/node/cycle  sink-stall=%0d%%", rate_pct, sink_stall_pct);
        $display("  packets sent=%0d received=%0d   flits sent=%0d received=%0d   errors=%0d",
                 sent_pkts, recv_pkts, sent_flits, recv_flits, errors);
        if (recv_pkts > 0)
            $display("  RESULT rate=%0d accepted=%.3f flits/node/cycle  avg_latency=%.1f cycles  max_latency=%0d",
                     rate_pct, 1.0 * sent_flits / (N * run_cycles), 1.0 * lat_sum / recv_pkts, lat_max);
        if (errors != 0 || sent_pkts != recv_pkts || sent_flits != recv_flits || recv_pkts == 0)
            $fatal(1, "TEST FAILED");
        $display("TEST PASSED");
        $finish;
    end
endmodule
