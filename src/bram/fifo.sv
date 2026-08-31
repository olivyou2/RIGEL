// FIFO using BRAM
module fifo#(
    parameter DATA_WIDTH=64,
    parameter DATA_DEPTH=512
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] data_in,
    input logic data_in_valid,
    output logic data_in_ready,

    output logic [DATA_WIDTH-1: 0] data_out,
    output logic data_out_valid,
    input logic data_out_ready 
);

    localparam DATA_DEPTH_WIDTH = $clog2(DATA_DEPTH);
    logic [DATA_WIDTH-1: 0] fifo[DATA_DEPTH];
    logic [DATA_WIDTH-1: 0] fifo_out;
    logic [DATA_DEPTH_WIDTH-1: 0] fifo_out_addr;
    logic [DATA_DEPTH_WIDTH-1: 0] fifo_out_addr_req;
    logic fifo_out_valid;

    assign fifo_out = fifo[fifo_out_addr_req];
    assign fifo_out_valid = fifo_out_addr_req == fifo_out_addr;

    assign data_out_valid = fifo_out_valid && !fifo_empty;

    logic [DATA_DEPTH_WIDTH-1: 0] fifo_read_offset;
    logic [DATA_DEPTH_WIDTH-1: 0] fifo_write_offset;
    logic [DATA_DEPTH_WIDTH-1: 0] fifo_count;

    logic fifo_empty;
    logic fifo_full;

    assign fifo_empty = fifo_count == 0;
    assign fifo_full = fifo_count == DATA_DEPTH;

    always @(posedge clk) begin
        fifo_out_addr_req   <= fifo_read_offset;
        fifo_out_addr       <= fifo_out_addr_req;
        data_out            <= fifo_out;
    end

    logic data_in_handshaked;
    logic data_out_handshaked;

    assign data_in_handshaked = data_in_valid && data_in_ready;
    assign data_out_handshaked = data_out_valid && data_out_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            data_in_ready <= 1;
            fifo_read_offset <= 0;
            fifo_write_offset <= 0;
        end else begin
            if (data_in_handshaked && !data_out_handshaked) begin
                fifo[fifo_write_offset] <= data_in;
                fifo_write_offset <= (fifo_write_offset + 1) % DATA_DEPTH;                
                fifo_count <= fifo_count + 1;
            end else if (!data_in_handshaked && data_out_handshaked) begin
                fifo_read_offset <= (fifo_read_offset + 1) % DATA_DEPTH;
                fifo_count <= fifo_count - 1;
            end else if (data_in_handshaked && data_out_handshaked) begin
                fifo[fifo_write_offset] <= data_in;
                fifo_write_offset <= (fifo_write_offset + 1) % DATA_DEPTH;
                fifo_read_offset <= (fifo_read_offset + 1) % DATA_DEPTH;
            end
        end
    end

endmodule