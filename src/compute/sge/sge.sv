module sge#(
    ADDR_WIDTH  = 32,
    DATA_WIDTH  = 64,
    REG_SIZE    = 128,   // 32*4, 64*2, 128*1, anyway
    REG_DEPTH   = 4,
    BATCH_MAX   = 512
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] sge_base_addr,
    input logic [$clog2(BATCH_MAX):0] sge_batch_size,
    input logic sge_valid,
    output logic sge_ready,

    output logic [ADDR_WIDTH-1: 0] read_req_addr,
    output logic read_req_valid,
    input logic read_req_ready,

    input logic [DATA_WIDTH-1: 0] read_rsp_data,
    input logic read_rsp_valid,
    output logic read_rsp_ready,

    output logic [REG_SIZE-1: 0] reg_out,
    output logic reg_valid,
    input logic reg_ready
);

    // Datapath
    //
    // SGE Contorl -> Addr Out
    // 
    // Data In -> Assembler -> FIFO -> Reg Out
    //     

    sge_control #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .BATCH_MAX (BATCH_MAX /* default 512 */)
     ) sge_control (
        .clk           (clk),
        .rst_n         (rst_n),
        .sge_base_addr (sge_base_addr),
        .sge_batch_size(sge_batch_size),
        .sge_valid     (sge_valid),
        .sge_ready     (sge_ready),
        .read_req_addr (read_req_addr),
        .read_req_valid(read_req_valid),
        .read_req_ready(read_req_ready),
        .sge_handshaked(reg_valid && reg_ready),
        .backend_ready (reg_ready)
    );

    logic [REG_SIZE-1: 0] fifo_in;
    logic fifo_in_valid;
    logic fifo_in_ready;

    sge_assemble #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .REG_SIZE  (REG_SIZE /* default 128 */)
     ) sge_assemble (
        .clk       (clk),
        .rst_n     (rst_n),
        .data_in   (read_rsp_data),
        .data_valid(read_rsp_valid),
        .data_ready(read_rsp_ready),
        .reg_out   (fifo_in),
        .reg_valid (fifo_in_valid),
        .reg_ready (fifo_in_ready)
    );

    fifo #(
        .DATA_WIDTH(REG_SIZE /* default 64 */),
        .DATA_DEPTH(REG_DEPTH /* default 512 */)
     ) fifo (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (fifo_in),
        .data_in_valid (fifo_in_valid),
        .data_in_ready (fifo_in_ready),
        .data_out      (reg_out),
        .data_out_valid(reg_valid),
        .data_out_ready(reg_ready)
    );

endmodule
