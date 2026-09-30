module bram_dp #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int DATA_DEPTH = 4096
) (
    input logic clk,

    // Each physical RAM port has one address: a read and a write on the same
    // port cannot target independent words in the same clock.
    input  logic [ADDR_WIDTH-1:0] addr_a,
    output logic [DATA_WIDTH-1:0] read_data_a,
    input  logic [DATA_WIDTH-1:0] write_data_a,
    input  logic                  write_enable_a,

    input  logic [ADDR_WIDTH-1:0] addr_b,
    output logic [DATA_WIDTH-1:0] read_data_b,
    input  logic [DATA_WIDTH-1:0] write_data_b,
    input  logic                  write_enable_b
);
    localparam int WORD_WIDTH      = $clog2(DATA_WIDTH) - 3;
    localparam int BRAM_ADDR_WIDTH = $clog2(DATA_DEPTH);

    logic [BRAM_ADDR_WIDTH-1:0] word_addr_a;
    logic [BRAM_ADDR_WIDTH-1:0] word_addr_b;

    assign word_addr_a = addr_a[WORD_WIDTH+BRAM_ADDR_WIDTH-1:WORD_WIDTH];
    assign word_addr_b = addr_b[WORD_WIDTH+BRAM_ADDR_WIDTH-1:WORD_WIDTH];

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] data [0:DATA_DEPTH-1];

    // READ_FIRST true dual-port template. Do not write the same word from both
    // ports in one cycle; FPGA collision behavior is device-specific.
    always_ff @(posedge clk) begin
        read_data_a <= data[word_addr_a];
        if (write_enable_a) data[word_addr_a] <= write_data_a;
    end

    always_ff @(posedge clk) begin
        read_data_b <= data[word_addr_b];
        if (write_enable_b) data[word_addr_b] <= write_data_b;
    end

endmodule
