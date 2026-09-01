module bram#(
    localparam ADDR_WIDTH=32,
    localparam DATA_WIDTH=64,

    localparam DATA_DEPTH=4096,

    localparam ADDR_CONTAINS_WORD_BYTES=1
)(
    input logic clk,
    
    input logic [ADDR_WIDTH-1: 0] read_addr,
    output logic [DATA_WIDTH-1: 0] read_data,

    input logic [ADDR_WIDTH-1: 0] write_addr,
    input logic [DATA_WIDTH-1: 0] write_data,
    input logic write_enable
);
    localparam WORD_WIDTH = $clog2(DATA_WIDTH)-3;
    localparam BRAM_ADDR_WIDTH = $clog2(DATA_DEPTH);
    
    logic [BRAM_ADDR_WIDTH-1: 0] read_word_addr;
    logic [BRAM_ADDR_WIDTH-1: 0] write_word_addr;

    assign read_word_addr = read_addr[WORD_WIDTH+BRAM_ADDR_WIDTH-1: WORD_WIDTH];
    assign write_word_addr = write_addr[WORD_WIDTH+BRAM_ADDR_WIDTH-1: WORD_WIDTH];

    logic [DATA_WIDTH-1: 0] data[DATA_DEPTH];

    always @(posedge clk) begin
        read_data <= data[read_word_addr];

        if (write_enable) begin
            data[write_word_addr] <= write_data;
        end
    end

endmodule