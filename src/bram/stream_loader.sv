module stream_loader#(
    parameter ADDR_WIDTH=32,
    parameter DATA_WIDTH=64,
    parameter IDX_WIDTH=8
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] read_addr_in,
    input logic read_addr_valid,
    output logic read_addr_ready,

    output logic [ADDR_WIDTH-1: 0] bram_addr_in,
    input logic [DATA_WIDTH-1: 0] bram_data_in,

    output logic [DATA_WIDTH-1: 0] loader_data_out,
    output logic loader_data_out_valid,
    input logic loader_data_out_ready
);
    always @(posedge clk) begin
        if (!rst_n) begin

        end else begin
            
        end
    end

endmodule