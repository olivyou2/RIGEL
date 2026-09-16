module mesh#(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 32,

    parameter MESH_W = 4,
    parameter MESH_H = 4,

    parameter X_BITS = 2,
    parameter Y_BITS = 2
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] node_in_data[MESH_W * MESH_H],
    input logic [ADDR_WIDTH-1: 0] node_in_addr[MESH_W * MESH_H],
    input logic node_in_valid[MESH_W * MESH_H],
    output logic node_in_ready[MESH_W * MESH_H],

    output logic [DATA_WIDTH-1: 0] node_out_data[MESH_W * MESH_H],
    output logic [ADDR_WIDTH-1: 0] node_out_addr[MESH_W * MESH_H],
    output logic node_out_valid[MESH_W * MESH_H],
    input logic node_out_ready[MESH_W * MESH_H]
);

    genvar x, y;
    // genvar y;

    localparam TOTAL_NODES = MESH_W * MESH_H;

    logic [DATA_WIDTH-1: 0] horizontal_data[TOTAL_NODES];
    logic [ADDR_WIDTH-1: 0] horizontal_addr[TOTAL_NODES];
    logic horizontal_data_valid[TOTAL_NODES];
    logic horizontal_data_ready[TOTAL_NODES];

    logic [DATA_WIDTH-1: 0] vertical_data[TOTAL_NODES];
    logic [ADDR_WIDTH-1: 0] vertical_addr[TOTAL_NODES];
    logic vertical_data_valid[TOTAL_NODES];
    logic vertical_data_ready[TOTAL_NODES];

    generate
        for (y=0; y<MESH_H; y++) begin
            for (x=0; x<MESH_W; x++) begin
                localparam int out_idx = x+y*MESH_W;
                localparam int north_in_idx = x+(y-1>=0?y-1:MESH_H-1)*MESH_W;
                localparam int west_in_idx = (x-1>=0?x-1:MESH_W-1)+y*MESH_W;

                mesh_router #(
                    .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
                    .DATA_WIDTH(DATA_WIDTH /* default 64 */),
                    .X_BITS    (X_BITS /* default 2 */),
                    .Y_BITS    (Y_BITS /* default 2 */),
                    .X         (x /* default 0 */),
                    .Y         (y /* default 0 */)
                 ) mesh_router (
                    .clk                 (clk),
                    .rst_n               (rst_n),
                    .north_in_addr       (vertical_addr[north_in_idx]),
                    .north_in_data       (vertical_data[north_in_idx]),
                    .north_in_valid    (vertical_data_valid[north_in_idx]),
                    .north_in_ready    (vertical_data_ready[north_in_idx]),
                    .west_in_addr        (horizontal_addr[west_in_idx]),
                    .west_in_data        (horizontal_data[west_in_idx]),
                    .west_in_valid     (horizontal_data_valid[west_in_idx]),
                    .west_in_ready     (horizontal_data_ready[west_in_idx]),
                    .east_out_addr       (horizontal_addr[out_idx]),
                    .east_out_data       (horizontal_data[out_idx]),
                    .east_out_valid     (horizontal_data_valid[out_idx]),
                    .east_out_ready     (horizontal_data_ready[out_idx]),
                    .south_out_addr      (vertical_addr[out_idx]),
                    .south_out_data      (vertical_data[out_idx]),
                    .south_out_valid    (vertical_data_valid[out_idx]),
                    .south_out_ready    (vertical_data_ready[out_idx]),
                    .local_in_addr       (node_in_addr[out_idx]),
                    .local_in_data       (node_in_data[out_idx]),
                    .local_in_valid (node_in_valid[out_idx]),
                    .local_in_ready (node_in_ready[out_idx]),
                    .local_out_addr      (node_out_addr[out_idx]),
                    .local_out_data      (node_out_data[out_idx]),
                    .local_out_valid(node_out_valid[out_idx]),
                    .local_out_ready(node_out_ready[out_idx])
                );
            end
        end
    endgenerate

endmodule