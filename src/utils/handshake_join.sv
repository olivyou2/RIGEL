module handshake_join#(
    parameter DATA_WIDTH = 64,
    parameter N = 4
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] data_in[N],
    input logic data_in_valid[N],
    output logic data_in_ready[N],

    output logic [DATA_WIDTH-1: 0] data_out[N],
    output logic data_out_valid,
    input logic data_out_ready
);
    logic [DATA_WIDTH-1: 0] skid_out_data[N];
    logic [N-1: 0] skid_out_valid;
    logic elem_skid_out_valid;
    logic elem_skid_out_ready;
    
    always @(*) begin
        elem_skid_out_valid = &skid_out_valid;
    end

    genvar i;
    generate
        for (i=0; i<N; i++) begin
            skid #(
                .DATA_WIDTH(DATA_WIDTH /* default 64 */)
             ) skid (
                .clk           (clk),
                .rst_n         (rst_n),
                .data_in       (data_in[i]),
                .data_in_valid (data_in_valid[i]),
                .data_in_ready (data_in_ready[i]),
                .data_out      (skid_out_data[i]),
                .data_out_valid(skid_out_valid[i]),
                .data_out_ready(elem_skid_out_valid && elem_skid_out_ready)
            );
        end
    endgenerate

    logic [DATA_WIDTH*N-1:0] joined_data_in;
    logic [DATA_WIDTH*N-1:0] joined_data_out;

    always @(*) begin
        for (int idx=0; idx<N; idx++) begin
            joined_data_in[idx*DATA_WIDTH +: DATA_WIDTH] = skid_out_data[idx];
        end


        for (int idx=0; idx<N; idx++) begin
            data_out[idx] = joined_data_out[idx*DATA_WIDTH +: DATA_WIDTH];
        end
    end

    skid #(
        .DATA_WIDTH(DATA_WIDTH*N /* default 64 */)
     ) skid_out (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (joined_data_in),
        .data_in_valid (elem_skid_out_valid),
        .data_in_ready (elem_skid_out_ready),
        .data_out      (joined_data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready)
    );

endmodule