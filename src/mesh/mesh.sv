module mesh #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 32,

    parameter MESH_W = 4,
    parameter MESH_H = 4,

    parameter X_BITS = 2,
    parameter Y_BITS = 2
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink in_ch[MESH_W * MESH_H],

    rv_if.source out_ch[MESH_W * MESH_H]
);
    localparam TOTAL_NODES = MESH_W * MESH_H;

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) horizontal[TOTAL_NODES] ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) vertical[TOTAL_NODES] ();

    genvar x, y;


    generate
        for (y = 0; y < MESH_H; y++) begin
            for (x = 0; x < MESH_W; x++) begin
                localparam int out_idx = x + y * MESH_W;
                localparam int north_in_idx = x + (y - 1 >= 0 ? y - 1 : MESH_H - 1) * MESH_W;
                localparam int west_in_idx = (x - 1 >= 0 ? x - 1 : MESH_W - 1) + y * MESH_W;

                mesh_router #(
                    .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
                    .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
                    .X_BITS    (X_BITS  /* default 2 */),
                    .Y_BITS    (Y_BITS  /* default 2 */),
                    .X         (x  /* default 0 */),
                    .Y         (y  /* default 0 */)
                ) mesh_router (
                    .clk(clk),
                    .rst_n(rst_n),
                    .north_ch(vertical[north_in_idx]),
                    .west_ch(horizontal[west_in_idx]),
                    .east_ch(horizontal[out_idx]),
                    .south_ch(vertical[out_idx]),
                    .local_in_ch(in_ch[out_idx]),
                    .local_out_ch(out_ch[out_idx])
                );
            end
        end
    endgenerate

endmodule
