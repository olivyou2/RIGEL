module compute#(
    parameter ADDR_WIDTH=32,
    parameter DATA_WIDTH=128
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] read_addr_in,
    input logic read_addr_valid,
    output logic read_addr_ready,

    output logic [DATA_WIDTH-1: 0] read_data_out,
    output logic read_data_valid,
    input logic read_data_ready,

    input logic [ADDR_WIDTH-1: 0] write_addr_in,
    input logic [DATA_WIDTH-1: 0] write_data_in,
    input logic write_data_valid,
    output logic write_data_ready
);
    localparam MASTER_N = 4;
    localparam SLAVE_N = 4;

    // IXC Wires
    logic [ADDR_WIDTH-1: 0] ixc_addr_out[MASTER_N];
    logic [1:0] ixc_slave_sel[MASTER_N];
    logic [SLAVE_N-1: 0] ixc_sel_read_onehot[MASTER_N];

    logic [ADDR_WIDTH-1: 0] ixc_write_addr_out[MASTER_N];
    logic [1:0] ixc_write_slave_sel[MASTER_N];
    logic [SLAVE_N-1: 0] ixc_sel_write_onehot[MASTER_N];

    logic [ADDR_WIDTH-1: 0] ixc_read_addr_in[MASTER_N];
    logic ixc_read_addr_valid[MASTER_N];
    logic ixc_read_addr_ready[MASTER_N];

    logic [DATA_WIDTH-1: 0] ixc_read_data_out[MASTER_N];
    logic ixc_read_data_valid[MASTER_N];
    logic ixc_read_data_ready[MASTER_N];

    logic [ADDR_WIDTH-1: 0] ixc_write_addr_in[MASTER_N];
    logic [DATA_WIDTH-1: 0] ixc_write_data_in[MASTER_N];
    logic ixc_write_data_valid[MASTER_N];
    logic ixc_write_data_ready[MASTER_N];

    logic [ADDR_WIDTH-1: 0] slave_read_addr_out[SLAVE_N];
    logic slave_read_addr_valid[SLAVE_N];
    logic slave_read_addr_ready[SLAVE_N];

    logic [DATA_WIDTH-1: 0] slave_read_data_in[SLAVE_N];
    logic slave_read_data_valid[SLAVE_N];
    logic slave_read_data_ready[SLAVE_N];

    logic [ADDR_WIDTH-1: 0] slave_write_addr_out[SLAVE_N];
    logic [DATA_WIDTH-1: 0] slave_write_data_out[SLAVE_N];
    logic slave_write_data_valid[SLAVE_N];
    logic slave_write_data_ready[SLAVE_N];

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
        .read_addr_in          (ixc_read_addr_in),
        .read_addr_valid       (ixc_read_addr_valid),
        .read_addr_ready       (ixc_read_addr_ready),
        .ixc_addr_out          (ixc_addr_out),
        .ixc_slave_sel         (ixc_slave_sel),
        .read_data_out         (ixc_read_data_out),
        .read_data_valid       (ixc_read_data_valid),
        .read_data_ready       (ixc_read_data_ready),
        .write_addr_in         (ixc_write_addr_in),
        .write_data_in         (ixc_write_data_in),
        .write_data_valid      (ixc_write_data_valid),
        .write_data_ready      (ixc_write_data_ready),
        .ixc_write_addr_out    (ixc_write_addr_out),
        .ixc_write_slave_sel   (ixc_write_slave_sel),
        .slave_read_addr_out   (slave_read_addr_out),
        .slave_read_addr_valid (slave_read_addr_valid),
        .slave_read_addr_ready (slave_read_addr_ready),
        .slave_read_data_in    (slave_read_data_in),
        .slave_read_data_valid (slave_read_data_valid),
        .slave_read_data_ready (slave_read_data_ready),
        .slave_write_addr_out  (slave_write_addr_out),
        .slave_write_data_out  (slave_write_data_out),
        .slave_write_data_valid(slave_write_data_valid),
        .slave_write_data_ready(slave_write_data_ready)
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
        .addr_in(ixc_addr_out),
        .sel_out(ixc_sel_read_onehot)
    );

    compute_ixc_sel #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MASTER_N(MASTER_N),
        .SLAVE_N(SLAVE_N)
    ) compute_ixc_sel_write (
        .addr_in(ixc_write_addr_out),
        .sel_out(ixc_sel_write_onehot)
    );

    for (genvar m=0; m<MASTER_N; m++) begin: gen_ixc_sel_encode
        assign ixc_slave_sel[m] = onehot_to_sel(ixc_sel_read_onehot[m]);
        assign ixc_write_slave_sel[m] = onehot_to_sel(ixc_sel_write_onehot[m]);
    end

    // Interface IXC Register
    assign ixc_read_addr_in[0] = read_addr_in;
    assign ixc_read_addr_valid[0] = read_addr_valid;
    assign read_addr_ready = ixc_read_addr_ready[0];

    assign read_data_out = ixc_read_data_out[0];
    assign read_data_valid = ixc_read_data_valid[0];
    assign ixc_read_data_ready[0] = read_data_ready;

    assign ixc_write_addr_in[0] = write_addr_in;
    assign ixc_write_data_in[0] = write_data_in;
    assign ixc_write_data_valid[0] = write_data_valid;
    assign write_data_ready = ixc_write_data_ready[0];

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
        .read_addr_in    (slave_read_addr_out[0]),
        .read_addr_valid (slave_read_addr_valid[0]),
        .read_addr_ready (slave_read_addr_ready[0]),
        .read_data_out   (slave_read_data_in[0]),
        .read_data_valid (slave_read_data_valid[0]),
        .read_data_ready (slave_read_data_ready[0]),
        .write_addr_in   (slave_write_addr_out[0]),
        .write_data_in   (slave_write_data_out[0]),
        .write_data_valid(slave_write_data_valid[0]),
        .write_data_ready(slave_write_data_ready[0]),
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
                .addr_out          (ixc_read_addr_in    [IXC_BASE_OFFSET + dma_idx]),
                .addr_out_valid    (ixc_read_addr_valid [IXC_BASE_OFFSET + dma_idx]),
                .addr_out_ready    (ixc_read_addr_ready [IXC_BASE_OFFSET + dma_idx]),
                .data_in           (ixc_read_data_out   [IXC_BASE_OFFSET + dma_idx]),
                .data_in_valid     (ixc_read_data_valid [IXC_BASE_OFFSET + dma_idx]),
                .data_in_ready     (ixc_read_data_ready [IXC_BASE_OFFSET + dma_idx]),
                .dma_addr_out      (ixc_write_addr_in   [IXC_BASE_OFFSET + dma_idx]),
                .dma_data_out      (ixc_write_data_in   [IXC_BASE_OFFSET + dma_idx]),
                .dma_data_out_valid(ixc_write_data_valid[IXC_BASE_OFFSET + dma_idx]),
                .dma_data_out_ready(ixc_write_data_ready[IXC_BASE_OFFSET + dma_idx]),
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
        .read_addr_in       (slave_read_addr_out[1]),
        .read_addr_in_valid (slave_read_addr_valid[1]),
        .read_addr_in_ready (slave_read_addr_ready[1]),
        .read_data_out      (slave_read_data_in[1]),
        .read_data_out_valid(slave_read_data_valid[1]),
        .read_data_out_ready(slave_read_data_ready[1]),
        .write_addr_in      (slave_write_addr_out[1]),
        .write_data_in      (slave_write_data_out[1]),
        .write_data_valid   (slave_write_data_valid[1]),
        .write_data_ready   (slave_write_data_ready[1])
    );

    // Matrix/Vector가 아직 미구현인 동안 IXC 입력을 deterministic 하게 유지한다.
    for (genvar s=2; s<SLAVE_N; s++) begin: gen_unimpl_slave_tieoff
        assign slave_read_addr_ready[s] = 1'b1;
        assign slave_read_data_in[s] = '0;
        assign slave_read_data_valid[s] = 1'b0;
        assign slave_write_data_ready[s] = 1'b1;
    end

endmodule
