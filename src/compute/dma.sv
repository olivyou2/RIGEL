module dma#(
    ADDR_WIDTH=32,
    DATA_WIDTH=64,
    REGS=4
)(
    input logic clk,
    input logic rst_n,

    // 1-clock latency BRAM bases
    output logic [ADDR_WIDTH-1: 0] in_addr,
    input logic [DATA_WIDTH-1: 0] in_data,

    output logic [ADDR_WIDTH-1: 0] out_addr,
    output logic [DATA_WIDTH-1: 0] out_data,
    output logic out_valid,
    input logic out_ready,

    // data-out port
    output logic [ADDR_WIDTH-1: 0] addr_in,

    // register map
    input logic [DATA_WIDTH-1: 0] regs[REGS],

    // control interface
    input logic dma_fire,
    input logic [ADDR_WIDTH-1: 0] dma_length,
    input logic [ADDR_WIDTH-1: 0] dma_src_addr,
    input logic [ADDR_WIDTH-1: 0] dma_dst_addr,
    
    output logic dma_ready
);

    // Compute DMA Map

    // 0X0002_0000 ~ 0002_7FFF  scratchpad C (R)
    // 0x0004_0000 ~ 0004_FFFF Registers
    //  +00     Compute status register
    //  +08     DMA status register
    //          [DECERR, RESERVATION]

    // Top Control
    logic read_issue;
    logic write_issue;

    // Control
    logic dma_src_addr_rst;
    logic dma_src_addr_inc;
    logic dma_dst_addr_rst;
    logic dma_dst_addr_inc;

    logic [1:0] dma_state;
    logic [ADDR_WIDTH-1: 0] dma_count;

    localparam STATE_IDLE   = 0;
    localparam STATE_RST    = 1;
    localparam STATE_WORK   = 2;

    always @(posedge clk) begin
        if (!rst_n) begin
            dma_state <= 0;
        end else begin
            // IDLE
            if (dma_state == STATE_IDLE) begin
                if (dma_fire) begin
                    dma_state <= STATE_WORK;
                end
            end
        end
    end

    // Addr Issue Engine
    always @(*) begin
        dma_src_addr_rst = 0;
        dma_dst_addr_rst = 0;
        dma_src_addr_inc = 0;
        dma_dst_addr_inc = 0;

        if (dma_state == STATE_IDLE && dma_fire) begin
            dma_src_addr_rst = 1;
            dma_dst_addr_rst = 1;
        end

        if (read_issue) begin
            dma_src_addr_inc = 1;
        end

        if (write_issue) begin
            dma_dst_addr_inc = 1;
        end
        
    end

    // Data path

    // Address Issue Engine
    always @(posedge clk) begin
        if (!rst_n) begin
        end else begin
            if (dma_src_addr_rst) begin
                in_addr <= dma_src_addr;
            end else if (dma_src_addr_inc) begin
                in_addr <= in_addr + 8;
            end
            
            if (dma_dst_addr_rst) begin
                out_addr <= dma_dst_addr;
            end else if (dma_dst_addr_inc) begin
                out_addr <= out_addr + 8;
            end
        end
    end

    // Read Engine -> FIFO
    assign fifo_data_in = in_data;

    // FIFO -> Write Engine
    assign out_data = fifo_data_out;

    // FIFO Instantiate
    logic fifo_data_in_valid;
    logic fifo_data_in_ready;
    logic [DATA_WIDTH-1: 0] fifo_data_in;

    logic fifo_data_out_valid;
    logic fifo_data_out_ready;
    logic [DATA_WIDTH-1: 0] fifo_data_out;

    fifo fifo_dut(
        .clk(clk),
        .rst_n(rst_n),
        
        .data_in(fifo_data_in),
        .data_in_valid(fifo_data_in_valid),
        .data_in_ready(fifo_data_in_ready),

        .data_out(fifo_data_out),
        .data_out_valid(fifo_data_out_valid),
        .data_out_ready(fifo_data_out_ready)
    );

endmodule