module mesh_router#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,

    parameter X_BITS=2,
    parameter Y_BITS=2,
    parameter [X_BITS-1:0] X=0,
    parameter [Y_BITS-1:0] Y=0
)(
    input logic clk,
    input logic rst_n,

    // External Router
    input logic [ADDR_WIDTH-1: 0] north_addr_in,
    input logic [DATA_WIDTH-1: 0] north_data_in,
    input logic north_data_valid,
    output logic north_data_ready,

    input logic [ADDR_WIDTH-1: 0] west_addr_in,
    input logic [DATA_WIDTH-1: 0] west_data_in,
    input logic west_data_valid,
    output logic west_data_ready,

    output logic [ADDR_WIDTH-1: 0] east_addr_out,
    output logic [DATA_WIDTH-1: 0] east_data_out,
    output logic east_data_valid,
    input logic east_data_ready,

    output logic [ADDR_WIDTH-1: 0] south_addr_out,
    output logic [DATA_WIDTH-1: 0] south_data_out,
    output logic south_data_valid,
    input logic south_data_ready,

    // Local In/Out
    input logic [ADDR_WIDTH-1: 0] local_addr_in,
    input logic [DATA_WIDTH-1: 0] local_data_in,
    input logic local_data_in_valid,
    output logic local_data_in_ready,

    output logic [ADDR_WIDTH-1: 0] local_addr_out,
    output logic [DATA_WIDTH-1: 0] local_data_out,
    output logic local_data_out_valid,
    input logic local_data_out_ready
);
    logic [DATA_WIDTH+ADDR_WIDTH-1: 0] data_wires[4];
    logic [3:0] data_valid_wires;

    assign data_wires[0] = {north_data_in, north_addr_in};
    assign data_wires[1] = {west_data_in, west_addr_in};
    assign data_wires[2] = {local_data_in, local_addr_in};
    assign data_wires[3] = 0;

    assign data_valid_wires = {1'b0, local_data_in_valid, west_data_valid, north_data_valid};

    logic east_arbiter_data_valid[4];
    logic east_arbiter_data_ready[4];

    logic south_arbiter_data_valid[4];
    logic south_arbiter_data_ready[4];

    logic local_arbiter_data_valid[4];
    logic local_arbiter_data_ready[4];

    logic arbiter_data_ready[4];

    function [X_BITS-1:0] extract_x_from_addr(input logic [ADDR_WIDTH-1: 0] addr);
        extract_x_from_addr = addr[ADDR_WIDTH-1 -: X_BITS];
    endfunction

    function [Y_BITS-1:0] extract_y_from_addr(input logic [ADDR_WIDTH-1: 0] addr);
        extract_y_from_addr = addr[ADDR_WIDTH-1-X_BITS -: Y_BITS];
    endfunction

    task automatic route_packet(input logic [ADDR_WIDTH-1: 0] address, input logic [1:0] sel);
        logic [X_BITS-1: 0] addr_x;
        logic [Y_BITS-1: 0] addr_y;
        
        addr_x = extract_x_from_addr(address);
        addr_y = extract_y_from_addr(address);

        if (X != addr_x) begin
            east_arbiter_data_valid[sel] = data_valid_wires[sel];
        end else if (Y != addr_y) begin
            south_arbiter_data_valid[sel] = data_valid_wires[sel];
        end else if (X == addr_x && Y == addr_y) begin
            local_arbiter_data_valid[sel] = data_valid_wires[sel];
        end
    endtask

    // Control
    
    always_comb begin
        for (int i=0; i<4; i++) begin
            east_arbiter_data_valid[i] = 0;
            south_arbiter_data_valid[i] = 0;
            local_arbiter_data_valid[i] = 0;
        end

        route_packet(north_addr_in, 0);
        route_packet(west_addr_in, 1);
        route_packet(local_addr_in, 2);

        arbiter_data_ready[0] = east_arbiter_data_ready[0] || south_arbiter_data_ready[0] || local_arbiter_data_ready[0];
        arbiter_data_ready[1] = east_arbiter_data_ready[1] || south_arbiter_data_ready[1] || local_arbiter_data_ready[1];
        arbiter_data_ready[2] = east_arbiter_data_ready[2] || south_arbiter_data_ready[2] || local_arbiter_data_ready[2];

        north_data_ready = arbiter_data_ready[0];
        west_data_ready = arbiter_data_ready[1];
        local_data_in_ready = arbiter_data_ready[2];
    end

    // all -> east arbiter
    arbiter_skid #(
        .DATA_WIDTH(DATA_WIDTH+ADDR_WIDTH /* default 64 */),
        .N         (4 /* default 2 */)
    ) arbiter_east_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_wires),
        .data_valid    (east_arbiter_data_valid),
        .data_ready    (east_arbiter_data_ready),
        .data_out      ({east_data_out, east_addr_out}),
        .data_out_valid(east_data_valid),
        .data_out_ready(east_data_ready)
    );

    // all -> south arbiter
    arbiter_skid #(
        .DATA_WIDTH(DATA_WIDTH+ADDR_WIDTH /* default 64 */),
        .N         (4 /* default 2 */)
    ) arbiter_south_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_wires),
        .data_valid    (south_arbiter_data_valid),
        .data_ready    (south_arbiter_data_ready),
        .data_out      ({south_data_out, south_addr_out}),
        .data_out_valid(south_data_valid),
        .data_out_ready(south_data_ready)
    );

    // all -> local arbiter
    arbiter_skid #(
        .DATA_WIDTH(DATA_WIDTH+ADDR_WIDTH /* default 64 */),
        .N         (4 /* default 2 */)
    ) arbiter_local_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_wires),
        .data_valid    (local_arbiter_data_valid),
        .data_ready    (local_arbiter_data_ready),
        .data_out      ({local_data_out, local_addr_out}),
        .data_out_valid(local_data_out_valid),
        .data_out_ready(local_data_out_ready)
    );

endmodule; 