module mesh_router #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,

    parameter X_BITS = 2,
    parameter Y_BITS = 2,
    parameter [X_BITS-1:0] X = 0,
    parameter [Y_BITS-1:0] Y = 0
) (
    input logic clk,
    input logic rst_n,

    // External Router
    rv_if.sink north_ch,

    rv_if.sink west_ch,

    rv_if.source east_ch,

    rv_if.source south_ch,

    // Local In/Out
    rv_if.sink local_in_ch,

    rv_if.source local_out_ch
);

    logic [DATA_WIDTH+ADDR_WIDTH-1:0] data_wires[4];
    logic [3:0] data_valid_wires;

    assign data_wires[0] = {north_ch.data, north_ch.addr};
    assign data_wires[1] = {west_ch.data, west_ch.addr};
    assign data_wires[2] = {local_in_ch.data, local_in_ch.addr};
    assign data_wires[3] = 0;

    assign data_valid_wires = {1'b0, local_in_ch.valid, west_ch.valid, north_ch.valid};

    logic east_arbiter_data_valid[4];
    logic east_arbiter_data_ready[4];

    logic south_arbiter_data_valid[4];
    logic south_arbiter_data_ready[4];

    logic local_arbiter_data_valid[4];
    logic local_arbiter_data_ready[4];

    logic arbiter_data_ready[4];

    function [X_BITS-1:0] extract_x_from_addr(input logic [ADDR_WIDTH-1:0] addr);
        extract_x_from_addr = addr[ADDR_WIDTH-1-:X_BITS];
    endfunction

    function [Y_BITS-1:0] extract_y_from_addr(input logic [ADDR_WIDTH-1:0] addr);
        extract_y_from_addr = addr[ADDR_WIDTH-1-X_BITS-:Y_BITS];
    endfunction

    task automatic route_packet(input logic [ADDR_WIDTH-1:0] address, input logic [1:0] sel);
        logic [X_BITS-1:0] addr_x;
        logic [Y_BITS-1:0] addr_y;

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
        for (int i = 0; i < 4; i++) begin
            east_arbiter_data_valid[i]  = 0;
            south_arbiter_data_valid[i] = 0;
            local_arbiter_data_valid[i] = 0;
        end

        route_packet(north_ch.addr, 0);
        route_packet(west_ch.addr, 1);
        route_packet(local_in_ch.addr, 2);

        arbiter_data_ready[0] = east_arbiter_data_ready[0] || south_arbiter_data_ready[0] || local_arbiter_data_ready[0];
        arbiter_data_ready[1] = east_arbiter_data_ready[1] || south_arbiter_data_ready[1] || local_arbiter_data_ready[1];
        arbiter_data_ready[2] = east_arbiter_data_ready[2] || south_arbiter_data_ready[2] || local_arbiter_data_ready[2];

        north_ch.ready = arbiter_data_ready[0];
        west_ch.ready = arbiter_data_ready[1];
        local_in_ch.ready = arbiter_data_ready[2];
    end

    // all -> east arbiter
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH + ADDR_WIDTH))
    ) arbiter_east_dut_in_ch[(4)] ();
    for (genvar ch_idx = 0; ch_idx < (4); ch_idx++) begin : connect_arbiter_east_dut_in_ch
        assign arbiter_east_dut_in_ch[ch_idx].data = data_wires[ch_idx];
        assign arbiter_east_dut_in_ch[ch_idx].valid = east_arbiter_data_valid[ch_idx];
        assign east_arbiter_data_ready[ch_idx] = arbiter_east_dut_in_ch[ch_idx].ready;
        assign arbiter_east_dut_in_ch[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH + ADDR_WIDTH))
    ) arbiter_east_dut_out_ch ();
    assign {east_ch.data, east_ch.addr} = arbiter_east_dut_out_ch.data;
    assign east_ch.valid = arbiter_east_dut_out_ch.valid;
    assign arbiter_east_dut_out_ch.ready = east_ch.ready;
    arbiter_skid #(
        .DATA_WIDTH(DATA_WIDTH + ADDR_WIDTH  /* default 64 */),
        .N         (4  /* default 2 */)
    ) arbiter_east_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(arbiter_east_dut_in_ch),
        .out_ch(arbiter_east_dut_out_ch)
    );

    // all -> south arbiter
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH + ADDR_WIDTH))
    ) arbiter_south_dut_in_ch[(4)] ();
    for (genvar ch_idx = 0; ch_idx < (4); ch_idx++) begin : connect_arbiter_south_dut_in_ch
        assign arbiter_south_dut_in_ch[ch_idx].data = data_wires[ch_idx];
        assign arbiter_south_dut_in_ch[ch_idx].valid = south_arbiter_data_valid[ch_idx];
        assign south_arbiter_data_ready[ch_idx] = arbiter_south_dut_in_ch[ch_idx].ready;
        assign arbiter_south_dut_in_ch[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH + ADDR_WIDTH))
    ) arbiter_south_dut_out_ch ();
    assign {south_ch.data, south_ch.addr} = arbiter_south_dut_out_ch.data;
    assign south_ch.valid = arbiter_south_dut_out_ch.valid;
    assign arbiter_south_dut_out_ch.ready = south_ch.ready;
    arbiter_skid #(
        .DATA_WIDTH(DATA_WIDTH + ADDR_WIDTH  /* default 64 */),
        .N         (4  /* default 2 */)
    ) arbiter_south_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(arbiter_south_dut_in_ch),
        .out_ch(arbiter_south_dut_out_ch)
    );

    // all -> local arbiter
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH + ADDR_WIDTH))
    ) arbiter_local_dut_in_ch[(4)] ();
    for (genvar ch_idx = 0; ch_idx < (4); ch_idx++) begin : connect_arbiter_local_dut_in_ch
        assign arbiter_local_dut_in_ch[ch_idx].data = data_wires[ch_idx];
        assign arbiter_local_dut_in_ch[ch_idx].valid = local_arbiter_data_valid[ch_idx];
        assign local_arbiter_data_ready[ch_idx] = arbiter_local_dut_in_ch[ch_idx].ready;
        assign arbiter_local_dut_in_ch[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH + ADDR_WIDTH))
    ) arbiter_local_dut_out_ch ();
    assign {local_out_ch.data, local_out_ch.addr} = arbiter_local_dut_out_ch.data;
    assign local_out_ch.valid = arbiter_local_dut_out_ch.valid;
    assign arbiter_local_dut_out_ch.ready = local_out_ch.ready;
    arbiter_skid #(
        .DATA_WIDTH(DATA_WIDTH + ADDR_WIDTH  /* default 64 */),
        .N         (4  /* default 2 */)
    ) arbiter_local_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(arbiter_local_dut_in_ch),
        .out_ch(arbiter_local_dut_out_ch)
    );

endmodule
;
