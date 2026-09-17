module dma #(
    ADDR_WIDTH = 32,
    DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n,

    // DMA -> ADDRES
    rv_if.source read_req,

    // DATA -> DMA
    rv_if.sink read_rsp,

    // DMA -> BUS
    rv_if.source write_req,

    // control interface
    dma_ctrl_if.sink ctrl
);

    // Compute DMA Map

    // 0X0002_0000 ~ 0002_7FFF  scratchpad C (R)
    // 0x0004_0000 ~ 0004_FFFF Registers
    //  +00     Compute status register
    //  +08     DMA status register
    //          [DECERR, RESERVATION]

    // Control
    logic addr_rst;
    logic [ADDR_WIDTH-1:0] addr_rst_src;
    logic [ADDR_WIDTH-1:0] addr_rst_dst;
    logic [ADDR_WIDTH-1:0] addr_rst_step;

    logic addr_src_valid;
    logic addr_src_ready;

    dma_control #(
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */)
    ) dma_control_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .ctrl                 (ctrl),
        .addr_rst             (addr_rst),
        .addr_rst_src         (addr_rst_src),
        .addr_rst_dst         (addr_rst_dst),
        .addr_rst_step        (addr_rst_step),
        .addr_src_valid       (addr_src_valid),
        .addr_src_ready       (addr_src_ready),
        .dma_dataout_handshake(write_req.valid && write_req.ready)
    );

    // Datapath connect

    dma_src_addr #(
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */)
    ) dma_src_addr_dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_rst(addr_rst),
        .addr_rst_src(addr_rst_src),
        .addr_rst_step(addr_rst_step),
        .fire_in_valid(addr_src_valid),
        .fire_in_ready(addr_src_ready),
        .read_req(read_req)
    );

    // FIFO Instantiate

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH)
    ) fifo_dut_out_ch ();

    fifo #(
        .DATA_WIDTH(DATA_WIDTH)
    ) fifo_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(read_rsp),
        .out_ch(fifo_dut_out_ch)
    );

    // DMA Addr

    dma_dst_addr #(
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */)
    ) dma_dst_addr_dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_rst(addr_rst),
        .addr_rst_dst(addr_rst_dst),
        .addr_rst_step(addr_rst_step),
        .in_ch(fifo_dut_out_ch),
        .out_ch(write_req)
    );

endmodule
