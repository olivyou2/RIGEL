module sge #(
    ADDR_WIDTH = 32,
    DATA_WIDTH = 64,
    REG_SIZE   = 128,  // 32*4, 64*2, 128*1, anyway
    REG_DEPTH  = 4,
    BATCH_MAX  = 512
) (
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1:0] sge_base_addr,
    input logic [$clog2(BATCH_MAX):0] sge_batch_size,
    input logic sge_valid,
    output logic sge_ready,

    rv_if.source read_req,

    rv_if.sink data_ch,

    rv_if.source reg_ch
);

    // Datapath
    //
    // SGE Contorl -> Addr Out
    //
    // Data In -> Assembler -> FIFO -> Reg Out
    //

    sge_control #(
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .BATCH_MAX (BATCH_MAX  /* default 512 */)
    ) sge_control (
        .clk(clk),
        .rst_n(rst_n),
        .sge_base_addr(sge_base_addr),
        .sge_batch_size(sge_batch_size),
        .sge_valid(sge_valid),
        .sge_ready(sge_ready),
        .sge_handshaked(reg_ch.valid && reg_ch.ready),
        .backend_ready(reg_ch.ready),
        .read_req(read_req)
    );

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(REG_SIZE)
    ) sge_assemble_reg_ch ();

    sge_assemble #(
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .REG_SIZE  (REG_SIZE  /* default 128 */)
    ) sge_assemble (
        .clk(clk),
        .rst_n(rst_n),
        .data_ch(data_ch),
        .reg_ch(sge_assemble_reg_ch)
    );

    fifo #(
        .DATA_WIDTH(REG_SIZE  /* default 64 */),
        .DATA_DEPTH(REG_DEPTH  /* default 512 */)
    ) fifo (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(sge_assemble_reg_ch),
        .out_ch(reg_ch)
    );

endmodule
