// N->1 arbiter

module arbiter_skid#(
    DATA_WIDTH=64,
    N=2
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] data_in[N],
    input logic data_valid[N],
    output logic data_ready[N],

    output logic [DATA_WIDTH-1: 0] data_out,
    output logic data_out_valid,
    input logic data_out_ready
);

    logic [DATA_WIDTH-1:0] skid_data_in;
    logic skid_data_in_valid;
    logic skid_data_in_ready;

    arbiter #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .N         (N /* default 2 */)
     ) arbiter (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .data_valid    (data_valid),
        .data_ready    (data_ready),
        .data_out      (skid_data_in),
        .data_out_valid(skid_data_in_valid),
        .data_out_ready(skid_data_in_ready)
    );

    skid #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) skid (
        .clk           (clk),
        .rst_n          (rst_n),
        .data_in       (skid_data_in),
        .data_in_valid (skid_data_in_valid),
        .data_in_ready (skid_data_in_ready),
        .data_out      (data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready)
    );

endmodule