module compute#(
    parameter ADDR_WIDTH=32,
    parameter DATA_WIDTH=128
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] read_req_addr,
    input logic read_req_valid,
    output logic read_req_ready,

    output logic [DATA_WIDTH-1: 0] read_rsp_data,
    output logic read_rsp_valid,
    input logic read_rsp_ready,

    input logic [ADDR_WIDTH-1: 0] write_req_addr,
    input logic [DATA_WIDTH-1: 0] write_req_data,
    input logic write_req_valid,
    output logic write_req_ready
);
    localparam MASTER_N = 4;
    localparam SLAVE_N = 4;

    // IXC Wires
    logic [ADDR_WIDTH-1: 0] read_decode_addr[MASTER_N];
    logic [1:0] read_decode_sel[MASTER_N];
    logic [SLAVE_N-1: 0] ixc_sel_read_onehot[MASTER_N];

    logic [ADDR_WIDTH-1: 0] write_decode_addr[MASTER_N];
    logic [1:0] write_decode_sel[MASTER_N];
    logic [SLAVE_N-1: 0] ixc_sel_write_onehot[MASTER_N];

    logic [ADDR_WIDTH-1: 0] ixc_read_req_addr[MASTER_N];
    logic ixc_read_req_valid[MASTER_N];
    logic ixc_read_req_ready[MASTER_N];

    logic [DATA_WIDTH-1: 0] ixc_read_rsp_data[MASTER_N];
    logic ixc_read_rsp_valid[MASTER_N];
    logic ixc_read_rsp_ready[MASTER_N];

    logic [ADDR_WIDTH-1: 0] ixc_write_req_addr[MASTER_N];
    logic [DATA_WIDTH-1: 0] ixc_write_req_data[MASTER_N];
    logic ixc_write_req_valid[MASTER_N];
    logic ixc_write_req_ready[MASTER_N];

    logic [ADDR_WIDTH-1: 0] slave_read_req_addr[SLAVE_N];
    logic slave_read_req_valid[SLAVE_N];
    logic slave_read_req_ready[SLAVE_N];

    logic [DATA_WIDTH-1: 0] slave_read_rsp_data[SLAVE_N];
    logic slave_read_rsp_valid[SLAVE_N];
    logic slave_read_rsp_ready[SLAVE_N];

    logic [ADDR_WIDTH-1: 0] slave_write_req_addr[SLAVE_N];
    logic [DATA_WIDTH-1: 0] slave_write_req_data[SLAVE_N];
    logic slave_write_req_valid[SLAVE_N];
    logic slave_write_req_ready[SLAVE_N];

    function automatic logic [1:0] onehot_to_sel(input logic [SLAVE_N-1:0] onehot);
        onehot_to_sel = '0;
        for (int s=0; s<SLAVE_N; s++) begin
            if (onehot[s]) onehot_to_sel = s[1:0];
        end
    endfunction

    // IXC Implementation
    ixc #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .MASTER_N  (MASTER_N /* default 2 */),
        .SLAVE_N   (SLAVE_N /* default 2 */)
     ) ixc (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .read_req_addr          (ixc_read_req_addr),
        .read_req_valid       (ixc_read_req_valid),
        .read_req_ready       (ixc_read_req_ready),
        .read_decode_addr          (read_decode_addr),
        .read_decode_sel         (read_decode_sel),
        .read_rsp_data         (ixc_read_rsp_data),
        .read_rsp_valid       (ixc_read_rsp_valid),
        .read_rsp_ready       (ixc_read_rsp_ready),
        .write_req_addr         (ixc_write_req_addr),
        .write_req_data         (ixc_write_req_data),
        .write_req_valid      (ixc_write_req_valid),
        .write_req_ready      (ixc_write_req_ready),
        .write_decode_addr    (write_decode_addr),
        .write_decode_sel   (write_decode_sel),
        .slave_read_req_addr   (slave_read_req_addr),
        .slave_read_req_valid (slave_read_req_valid),
        .slave_read_req_ready (slave_read_req_ready),
        .slave_read_rsp_data    (slave_read_rsp_data),
        .slave_read_rsp_valid (slave_read_rsp_valid),
        .slave_read_rsp_ready (slave_read_rsp_ready),
        .slave_write_req_addr  (slave_write_req_addr),
        .slave_write_req_data  (slave_write_req_data),
        .slave_write_req_valid(slave_write_req_valid),
        .slave_write_req_ready(slave_write_req_ready)
    );

    // Interface            ->                  -> BRAM scratchpad  [1]
    //                      ->        IXC       -> Matrix Engine
    // DMA (3 channel)      ->                  -> Vector Engine
    //                      ->                  -> DMA Control      [0]

    compute_ixc_sel #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MASTER_N(MASTER_N),
        .SLAVE_N(SLAVE_N)
    ) compute_ixc_sel_read (
        .addr_in(read_decode_addr),
        .sel_out(ixc_sel_read_onehot)
    );

    compute_ixc_sel #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MASTER_N(MASTER_N),
        .SLAVE_N(SLAVE_N)
    ) compute_ixc_sel_write (
        .addr_in(write_decode_addr),
        .sel_out(ixc_sel_write_onehot)
    );

    for (genvar m=0; m<MASTER_N; m++) begin: gen_ixc_sel_encode
        assign read_decode_sel[m] = onehot_to_sel(ixc_sel_read_onehot[m]);
        assign write_decode_sel[m] = onehot_to_sel(ixc_sel_write_onehot[m]);
    end

    // Interface IXC Register
    assign ixc_read_req_addr[0] = read_req_addr;
    assign ixc_read_req_valid[0] = read_req_valid;
    assign read_req_ready = ixc_read_req_ready[0];

    assign read_rsp_data = ixc_read_rsp_data[0];
    assign read_rsp_valid = ixc_read_rsp_valid[0];
    assign ixc_read_rsp_ready[0] = read_rsp_ready;

    assign ixc_write_req_addr[0] = write_req_addr;
    assign ixc_write_req_data[0] = write_req_data;
    assign ixc_write_req_valid[0] = write_req_valid;
    assign write_req_ready = ixc_write_req_ready[0];

    // DMA Implementation & Wiring

    genvar dma_idx;

    localparam DMA_N = 3;
    localparam IXC_BASE_OFFSET = 1;

    logic dma_fire_valid[DMA_N];
    logic dma_fire_ready[DMA_N];
    logic [ADDR_WIDTH-1: 0] dma_addr_src[DMA_N];
    logic [ADDR_WIDTH-1: 0] dma_addr_dst[DMA_N];
    logic [ADDR_WIDTH-1: 0] dma_step[DMA_N];
    logic [ADDR_WIDTH-1: 0] dma_length[DMA_N];

    dma_ixc_control #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 32 */),
        .DMA_N     (DMA_N /* default 3 */)
     ) dma_ixc_control (
        .clk             (clk),
        .rst_n           (rst_n),
        .read_req_addr    (slave_read_req_addr[0]),
        .read_req_valid (slave_read_req_valid[0]),
        .read_req_ready (slave_read_req_ready[0]),
        .read_rsp_data   (slave_read_rsp_data[0]),
        .read_rsp_valid (slave_read_rsp_valid[0]),
        .read_rsp_ready (slave_read_rsp_ready[0]),
        .write_req_addr   (slave_write_req_addr[0]),
        .write_req_data   (slave_write_req_data[0]),
        .write_req_valid(slave_write_req_valid[0]),
        .write_req_ready(slave_write_req_ready[0]),
        .fire_length     (dma_length),
        .fire_step       (dma_step),
        .fire_addr_src   (dma_addr_src),
        .fire_addr_dst   (dma_addr_dst),
        .dma_fire        (dma_fire_valid),
        .dma_ready       (dma_fire_ready)
    );

    generate
        for (dma_idx=0; dma_idx<DMA_N; dma_idx++) begin: gen_dma
            dma #(
                .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
                .DATA_WIDTH(DATA_WIDTH)
            ) dma (
                .clk               (clk),
                .rst_n             (rst_n),
                .read_req_addr(ixc_read_req_addr    [IXC_BASE_OFFSET + dma_idx]),
                .read_req_valid(ixc_read_req_valid [IXC_BASE_OFFSET + dma_idx]),
                .read_req_ready(ixc_read_req_ready [IXC_BASE_OFFSET + dma_idx]),
                .read_rsp_data(ixc_read_rsp_data   [IXC_BASE_OFFSET + dma_idx]),
                .read_rsp_valid(ixc_read_rsp_valid [IXC_BASE_OFFSET + dma_idx]),
                .read_rsp_ready(ixc_read_rsp_ready [IXC_BASE_OFFSET + dma_idx]),
                .write_req_addr(ixc_write_req_addr   [IXC_BASE_OFFSET + dma_idx]),
                .write_req_data(ixc_write_req_data   [IXC_BASE_OFFSET + dma_idx]),
                .write_req_valid(ixc_write_req_valid[IXC_BASE_OFFSET + dma_idx]),
                .write_req_ready(ixc_write_req_ready[IXC_BASE_OFFSET + dma_idx]),
                .fire_valid        (dma_fire_valid[dma_idx]),
                .fire_ready        (dma_fire_ready[dma_idx]),
                .fire_length       (dma_length[dma_idx]),
                .fire_step         (dma_step[dma_idx]),
                .fire_addr_src     (dma_addr_src[dma_idx]),
                .fire_addr_dst     (dma_addr_dst[dma_idx])
            );
        end
    endgenerate

    // BRAM scratchpad slave
    bram_stream #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .DATA_DEPTH(2048)   // 32KB
     ) bram_stream (
        .clk                (clk),
        .rst_n              (rst_n),
        .read_req_addr       (slave_read_req_addr[1]),
        .read_req_valid (slave_read_req_valid[1]),
        .read_req_ready (slave_read_req_ready[1]),
        .read_rsp_data      (slave_read_rsp_data[1]),
        .read_rsp_valid(slave_read_rsp_valid[1]),
        .read_rsp_ready(slave_read_rsp_ready[1]),
        .write_req_addr      (slave_write_req_addr[1]),
        .write_req_data      (slave_write_req_data[1]),
        .write_req_valid   (slave_write_req_valid[1]),
        .write_req_ready   (slave_write_req_ready[1])
    );

    // Matrix/Vector가 아직 미구현인 동안 IXC 입력을 deterministic 하게 유지한다.
    for (genvar s=2; s<SLAVE_N; s++) begin: gen_unimpl_slave_tieoff
        assign slave_read_req_ready[s] = 1'b1;
        assign slave_read_rsp_data[s] = '0;
        assign slave_read_rsp_valid[s] = 1'b0;
        assign slave_write_req_ready[s] = 1'b1;
    end

endmodule
