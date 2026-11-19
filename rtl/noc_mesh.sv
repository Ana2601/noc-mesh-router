// NX x NY mesh of noc_router instances. Only the local ports are exposed.
// Node (x,y) uses index n = x + NX*y.
module noc_mesh #(
    parameter integer NX     = 4,
    parameter integer NY     = 4,
    parameter integer DATA_W = 32,
    parameter integer DEPTH  = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire [NX*NY-1:0]            loc_in_valid,
    output wire [NX*NY-1:0]            loc_in_ready,
    input  wire [NX*NY*(DATA_W+2)-1:0] loc_in_flit,
    output wire [NX*NY-1:0]            loc_out_valid,
    input  wire [NX*NY-1:0]            loc_out_ready,
    output wire [NX*NY*(DATA_W+2)-1:0] loc_out_flit
);
    localparam integer FW = DATA_W + 2;
    localparam integer N  = NX * NY;

    // per-router port bundles
    wire [4:0]      iv [0:N-1], ir [0:N-1], ov [0:N-1], ordy [0:N-1];
    wire [5*FW-1:0] ifl [0:N-1], ofl [0:N-1];

    genvar x, y;
    generate
        for (y = 0; y < NY; y = y + 1) begin : g_y
            for (x = 0; x < NX; x = x + 1) begin : g_x
                localparam integer n = x + NX * y;

                noc_router #(.DATA_W(DATA_W), .DEPTH(DEPTH)) u_router (
                    .clk(clk), .rst_n(rst_n), .my_x(x[3:0]), .my_y(y[3:0]),
                    .in_valid(iv[n]), .in_ready(ir[n]), .in_flit(ifl[n]),
                    .out_valid(ov[n]), .out_ready(ordy[n]), .out_flit(ofl[n])
                );

                // local port
                assign iv[n][0]           = loc_in_valid[n];
                assign ifl[n][0 +: FW]    = loc_in_flit[n*FW +: FW];
                assign loc_in_ready[n]    = ir[n][0];
                assign loc_out_valid[n]   = ov[n][0];
                assign loc_out_flit[n*FW +: FW] = ofl[n][0 +: FW];
                assign ordy[n][0]         = loc_out_ready[n];

                // north neighbour (x, y+1): my N output feeds its S input
                if (y < NY - 1) begin : g_n
                    assign iv[n][1]          = ov[n+NX][3];
                    assign ifl[n][1*FW +: FW] = ofl[n+NX][3*FW +: FW];
                    assign ordy[n][1]        = ir[n+NX][3];
                end else begin : g_n_edge
                    assign iv[n][1] = 1'b0; assign ifl[n][1*FW +: FW] = {FW{1'b0}}; assign ordy[n][1] = 1'b0;
                end
                // east neighbour (x+1, y)
                if (x < NX - 1) begin : g_e
                    assign iv[n][2]          = ov[n+1][4];
                    assign ifl[n][2*FW +: FW] = ofl[n+1][4*FW +: FW];
                    assign ordy[n][2]        = ir[n+1][4];
                end else begin : g_e_edge
                    assign iv[n][2] = 1'b0; assign ifl[n][2*FW +: FW] = {FW{1'b0}}; assign ordy[n][2] = 1'b0;
                end
                // south neighbour (x, y-1)
                if (y > 0) begin : g_s
                    assign iv[n][3]          = ov[n-NX][1];
                    assign ifl[n][3*FW +: FW] = ofl[n-NX][1*FW +: FW];
                    assign ordy[n][3]        = ir[n-NX][1];
                end else begin : g_s_edge
                    assign iv[n][3] = 1'b0; assign ifl[n][3*FW +: FW] = {FW{1'b0}}; assign ordy[n][3] = 1'b0;
                end
                // west neighbour (x-1, y)
                if (x > 0) begin : g_w
                    assign iv[n][4]          = ov[n-1][2];
                    assign ifl[n][4*FW +: FW] = ofl[n-1][2*FW +: FW];
                    assign ordy[n][4]        = ir[n-1][2];
                end else begin : g_w_edge
                    assign iv[n][4] = 1'b0; assign ifl[n][4*FW +: FW] = {FW{1'b0}}; assign ordy[n][4] = 1'b0;
                end
            end
        end
    endgenerate
endmodule
