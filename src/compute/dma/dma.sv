module dma#(
    ADDR_WIDTH=32,
    DATA_WIDTH=64
)(
    input logic clk,
    input logic rst_n,

    // DMA -> read request
    output logic [ADDR_WIDTH-1: 0] read_req_addr,
    output logic read_req_valid,
    input logic read_req_ready,

    // read response -> DMA
    input logic [DATA_WIDTH-1: 0] read_rsp_data,
    input logic read_rsp_valid,
    output logic read_rsp_ready,

    // DMA -> write request
    output logic [ADDR_WIDTH-1: 0] write_req_addr,
    output logic [DATA_WIDTH-1: 0] write_req_data,
    output logic write_req_valid,
    input logic write_req_ready,

    // control interface
    input logic fire_valid,
    output logic fire_ready,

    input logic [ADDR_WIDTH-1: 0] fire_length,
    input logic [ADDR_WIDTH-1: 0] fire_step,
    input logic [ADDR_WIDTH-1: 0] fire_addr_src,
    input logic [ADDR_WIDTH-1: 0] fire_addr_dst
);

    // Compute DMA Map

    // 0X0002_0000 ~ 0002_7FFF  scratchpad C (R)
    // 0x0004_0000 ~ 0004_FFFF Registers
    //  +00     Compute status register
    //  +08     DMA status register
    //          [DECERR, RESERVATION]

    // Control
    logic addr_rst;
    logic [ADDR_WIDTH-1: 0] addr_rst_src;
    logic [ADDR_WIDTH-1: 0] addr_rst_dst;
    logic [ADDR_WIDTH-1: 0] addr_rst_step;

    logic addr_src_valid;
    logic addr_src_ready;

    dma_control #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */)
    ) dma_control_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .fire_valid    (fire_valid),
        .fire_ready    (fire_ready),
        .fire_addr_src (fire_addr_src),
        .fire_addr_dst (fire_addr_dst),
        .fire_step     (fire_step),
        .fire_length   (fire_length),
        .addr_rst      (addr_rst),
        .addr_rst_src  (addr_rst_src),
        .addr_rst_dst  (addr_rst_dst),
        .addr_rst_step (addr_rst_step),
        .addr_src_valid(addr_src_valid),
        .addr_src_ready(addr_src_ready),
        .dma_dataout_handshake(write_req_valid && write_req_ready)
    );

    // Datapath connect
    dma_src_addr #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */)
    ) dma_src_addr_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr_rst      (addr_rst),
        .addr_rst_src  (addr_rst_src),
        .addr_rst_step (addr_rst_step),
        .fire_in_valid (addr_src_valid),
        .fire_in_ready (addr_src_ready),
        .read_req_addr (read_req_addr),
        .read_req_valid(read_req_valid),
        .read_req_ready(read_req_ready)
    );

    // FIFO Instantiate
    logic fifo_data_out_valid;
    logic fifo_data_out_ready;
    logic [DATA_WIDTH-1: 0] fifo_data_out;

    fifo #(
        .DATA_WIDTH(DATA_WIDTH)
    ) fifo_dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .data_in(read_rsp_data),
        .data_in_valid(read_rsp_valid),
        .data_in_ready(read_rsp_ready),

        .data_out(fifo_data_out),
        .data_out_valid(fifo_data_out_valid),
        .data_out_ready(fifo_data_out_ready)
    );

    // DMA Addr

    dma_dst_addr #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */)
    ) dma_dst_addr_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr_rst      (addr_rst),
        .addr_rst_dst  (addr_rst_dst),
        .addr_rst_step (addr_rst_step),
        .data_in       (fifo_data_out),
        .data_in_valid (fifo_data_out_valid),
        .data_in_ready (fifo_data_out_ready),
        .write_req_data (write_req_data),
        .write_req_addr (write_req_addr),
        .write_req_valid(write_req_valid),
        .write_req_ready(write_req_ready)
    );

endmodule
