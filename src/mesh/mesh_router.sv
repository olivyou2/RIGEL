module mesh_router#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter CHANNELS = 2,

    parameter X_BITS=2,
    parameter Y_BITS=2,
    parameter X=0,
    parameter Y=0,

    parameter FIFO_DEPTH=8
)(
    input logic clk,
    input logic rst_n,

    // External Router
    input logic [ADDR_WIDTH-1: 0] north_addr_in[CHANNELS],
    input logic [DATA_WIDTH-1: 0] north_data_in[CHANNELS],
    input logic north_data_valid[CHANNELS],
    output logic north_data_ready[CHANNELS],

    input logic [ADDR_WIDTH-1: 0] west_addr_in[CHANNELS],
    input logic [DATA_WIDTH-1: 0] west_data_in[CHANNELS],
    input logic west_data_valid[CHANNELS],
    output logic west_data_ready[CHANNELS],

    output logic [ADDR_WIDTH-1: 0] east_addr_out[CHANNELS],
    output logic [DATA_WIDTH-1: 0] east_data_out[CHANNELS],
    output logic east_data_valid[CHANNELS],
    input logic east_data_ready[CHANNELS],

    output logic [ADDR_WIDTH-1: 0] south_addr_out[CHANNELS],
    output logic [DATA_WIDTH-1: 0] south_data_out[CHANNELS],
    output logic south_data_valid[CHANNELS],
    input logic south_data_ready[CHANNELS],

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

    genvar channel;
    generate
        for (channel=0; channel<CHANNELS; channel++) begin
            
        end
    endgenerate

endmodule;