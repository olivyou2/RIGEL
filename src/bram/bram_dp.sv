module bram_dp #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int DATA_DEPTH = 4096
) (
    input logic clk,

    input  logic [ADDR_WIDTH-1:0] read_addr_a,
    output logic [DATA_WIDTH-1:0] read_data_a,
    input  logic [ADDR_WIDTH-1:0] write_addr_a,
    input  logic [DATA_WIDTH-1:0] write_data_a,
    input  logic                  write_enable_a,

    input  logic [ADDR_WIDTH-1:0] read_addr_b,
    output logic [DATA_WIDTH-1:0] read_data_b,
    input  logic [ADDR_WIDTH-1:0] write_addr_b,
    input  logic [DATA_WIDTH-1:0] write_data_b,
    input  logic                  write_enable_b
);
    localparam int WORD_WIDTH      = $clog2(DATA_WIDTH) - 3;
    localparam int BRAM_ADDR_WIDTH = $clog2(DATA_DEPTH);

    logic [BRAM_ADDR_WIDTH-1:0] read_word_addr_a;
    logic [BRAM_ADDR_WIDTH-1:0] write_word_addr_a;
    logic [BRAM_ADDR_WIDTH-1:0] read_word_addr_b;
    logic [BRAM_ADDR_WIDTH-1:0] write_word_addr_b;

    assign read_word_addr_a =
        read_addr_a[WORD_WIDTH+BRAM_ADDR_WIDTH-1:WORD_WIDTH];
    assign write_word_addr_a =
        write_addr_a[WORD_WIDTH+BRAM_ADDR_WIDTH-1:WORD_WIDTH];
    assign read_word_addr_b =
        read_addr_b[WORD_WIDTH+BRAM_ADDR_WIDTH-1:WORD_WIDTH];
    assign write_word_addr_b =
        write_addr_b[WORD_WIDTH+BRAM_ADDR_WIDTH-1:WORD_WIDTH];

    logic [DATA_WIDTH-1:0] data [0:DATA_DEPTH-1];

    // Both ports have a synchronous read and an independent write path.
    // Avoid writing the same word from both ports in one cycle. The simulation
    // model resolves that collision in favor of port B, but FPGA BRAM collision
    // behavior can be device-specific.
    always_ff @(posedge clk) begin
        read_data_a <= data[read_word_addr_a];
        read_data_b <= data[read_word_addr_b];

        if (write_enable_a) begin
            data[write_word_addr_a] <= write_data_a;
        end

        if (write_enable_b) begin
            data[write_word_addr_b] <= write_data_b;
        end
    end

endmodule
