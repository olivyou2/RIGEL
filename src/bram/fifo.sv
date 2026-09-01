// FIFO using BRAM
module fifo #(
    parameter DATA_WIDTH = 64,
    parameter DATA_DEPTH = 512
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic [DATA_WIDTH-1:0] data_in,
    input  logic                  data_in_valid,
    output logic                  data_in_ready,

    output logic [DATA_WIDTH-1:0] data_out,
    output logic                  data_out_valid,
    input  logic                  data_out_ready
);

    localparam ADDR_WIDTH  = (DATA_DEPTH > 1) ? $clog2(DATA_DEPTH) : 1;
    localparam COUNT_WIDTH = $clog2(DATA_DEPTH + 1);
    localparam logic [ADDR_WIDTH-1:0] LAST_ADDR = ADDR_WIDTH'(DATA_DEPTH - 1);

    logic [DATA_WIDTH-1:0] fifo_mem [DATA_DEPTH];
    logic [ADDR_WIDTH-1:0] fifo_read_offset;
    logic [ADDR_WIDTH-1:0] fifo_write_offset;
    logic [COUNT_WIDTH-1:0] fifo_count;

    logic [DATA_WIDTH-1:0] bram_out_data;
    logic                  read_pending;
    logic                  issue_read;
    logic [DATA_WIDTH-1:0] output_data_0;
    logic [DATA_WIDTH-1:0] output_data_1;
    logic [1:0]            output_count;
    logic                  data_in_handshaked;
    logic                  data_out_handshaked;
    logic                  fifo_full;

    assign fifo_full = (fifo_count == DATA_DEPTH);

    assign data_in_ready       = !fifo_full;
    assign data_in_handshaked  = data_in_valid && data_in_ready;
    assign data_out_handshaked = data_out_valid && data_out_ready;
    assign data_out_valid      = (output_count != 0);
    assign data_out            = output_data_0;

    // fifo_count covers memory, the in-flight read, and both output slots.
    // Reserve a slot for every issued read so backpressure cannot overflow them.
    assign issue_read = (fifo_count > (COUNT_WIDTH'(output_count)
                                     + COUNT_WIDTH'(read_pending)))
                     && (((output_count + read_pending) < 2)
                         || data_out_handshaked);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_read_offset  <= '0;
            fifo_write_offset <= '0;
            fifo_count        <= '0;
        end else begin
            if (data_in_handshaked) begin
                fifo_mem[fifo_write_offset] <= data_in;
                if (fifo_write_offset == LAST_ADDR)
                    fifo_write_offset <= '0;
                else
                    fifo_write_offset <= fifo_write_offset + 1'b1;
            end

            if (issue_read) begin
                if (fifo_read_offset == LAST_ADDR)
                    fifo_read_offset <= '0;
                else
                    fifo_read_offset <= fifo_read_offset + 1'b1;
            end

            case ({data_in_handshaked, data_out_handshaked})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // Synchronous BRAM read: the requested word is available after the edge.
    always_ff @(posedge clk) begin
        if (issue_read)
            bram_out_data <= fifo_mem[fifo_read_offset];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_pending <= 1'b0;
            output_data_0 <= '0;
            output_data_1 <= '0;
            output_count  <= '0;
        end else begin
            read_pending <= issue_read;

            case ({read_pending, data_out_handshaked})
                2'b10: begin
                    if (output_count == 0)
                        output_data_0 <= bram_out_data;
                    else
                        output_data_1 <= bram_out_data;
                    output_count <= output_count + 1'b1;
                end
                2'b01: begin
                    if (output_count == 2)
                        output_data_0 <= output_data_1;
                    output_count <= output_count - 1'b1;
                end
                2'b11: begin
                    if (output_count == 1) begin
                        output_data_0 <= bram_out_data;
                    end else begin
                        output_data_0 <= output_data_1;
                        output_data_1 <= bram_out_data;
                    end
                end
                default: output_count <= output_count;
            endcase
        end
    end

endmodule
