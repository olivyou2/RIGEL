module compute #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink read_req,

    rv_if.source read_rsp,

    rv_if.sink write_req
);
    localparam MASTER_N = 4;
    localparam SLAVE_N = 4;

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) ixc_read_req[MASTER_N] ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) ixc_read_rsp[MASTER_N] ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) ixc_write_req[MASTER_N] ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) ixc_slave_read_req[SLAVE_N] ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) ixc_slave_read_rsp[SLAVE_N] ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) ixc_slave_write_req[SLAVE_N] ();
    assign ixc_read_req[0].data = '0;

    assign read_rsp.addr = '0;


    // IXC Wires
    logic [ADDR_WIDTH-1:0] ixc_addr_out[MASTER_N];
    logic [1:0] ixc_slave_sel[MASTER_N];
    logic [SLAVE_N-1:0] ixc_sel_read_onehot[MASTER_N];

    logic [ADDR_WIDTH-1:0] ixc_write_addr_out[MASTER_N];
    logic [1:0] ixc_write_slave_sel[MASTER_N];
    logic [SLAVE_N-1:0] ixc_sel_write_onehot[MASTER_N];

    function automatic logic [1:0] onehot_to_sel(input logic [SLAVE_N-1:0] onehot);
        onehot_to_sel = '0;
        for (int s = 0; s < SLAVE_N; s++) begin
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
        .clk(clk),
        .rst_n(rst_n),
        .ixc_addr_out(ixc_addr_out),
        .ixc_slave_sel(ixc_slave_sel),
        .ixc_write_addr_out(ixc_write_addr_out),
        .ixc_write_slave_sel(ixc_write_slave_sel),
        .read_req(ixc_read_req),
        .read_rsp(ixc_read_rsp),
        .write_req(ixc_write_req),
        .slave_read_req(ixc_slave_read_req),
        .slave_read_rsp(ixc_slave_read_rsp),
        .slave_write_req(ixc_slave_write_req)
    );

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

    for (genvar m = 0; m < MASTER_N; m++) begin : gen_ixc_sel_encode
        assign ixc_slave_sel[m] = onehot_to_sel(ixc_sel_read_onehot[m]);
        assign ixc_write_slave_sel[m] = onehot_to_sel(ixc_sel_write_onehot[m]);
    end

    // Interface IXC Register
    assign ixc_read_req[0].addr = read_req.addr;
    assign ixc_read_req[0].valid = read_req.valid;
    assign read_req.ready = ixc_read_req[0].ready;

    assign read_rsp.data = ixc_read_rsp[0].data;
    assign read_rsp.valid = ixc_read_rsp[0].valid;
    assign ixc_read_rsp[0].ready = read_rsp.ready;

    assign ixc_write_req[0].addr = write_req.addr;
    assign ixc_write_req[0].data = write_req.data;
    assign ixc_write_req[0].valid = write_req.valid;
    assign write_req.ready = ixc_write_req[0].ready;

    // DMA Implementation & Wiring

    genvar dma_idx;

    localparam DMA_N = 1;
    localparam DMA_BASE_OFFSET = 1;

    dma_ctrl_if #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dma_ctrl[DMA_N] ();

    dma_ixc_control #(
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH  /* default 32 */),
        .DMA_N     (DMA_N  /* default 3 */)
    ) dma_ixc_control (
        .clk(clk),
        .rst_n(rst_n),
        .dma_ctrl(dma_ctrl),
        .read_req(ixc_slave_read_req[0]),
        .read_rsp(ixc_slave_read_rsp[0]),
        .write_req(ixc_slave_write_req[0])
    );

    generate
        for (dma_idx = 0; dma_idx < DMA_N; dma_idx++) begin : gen_dma

            dma #(
                .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
                .DATA_WIDTH(DATA_WIDTH)
            ) dma (
                .clk(clk),
                .rst_n(rst_n),
                .ctrl(dma_ctrl[dma_idx]),
                .read_req(ixc_read_req[DMA_BASE_OFFSET+dma_idx]),
                .read_rsp(ixc_read_rsp[DMA_BASE_OFFSET+dma_idx]),
                .write_req(ixc_write_req[DMA_BASE_OFFSET+dma_idx])
            );
        end
    endgenerate

    // vector #(
    //     .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
    //     .DATA_WIDTH(DATA_WIDTH /* default 128 */)
    //  ) vector (
    //     .clk                (clk),
    //     .rst_n              (rst_n),
    //     .read_req           (ixc_slave_read_req[2]),
    //     .read_rsp           (ixc_slave_read_rsp[2]),
    //     .write_req          (ixc_slave_write_req[2]),
    //     .bram_addr_write_req(bram_addr_write_req)
    // );

    vector_core #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 128 */),
        .LANE_WIDTH(8 /* default 8 */),
        .LANE_SIZE (16 /* default 16 */)
     ) vector_core (
        .clk   (clk),
        .rst_n (rst_n),
        .read_req (ixc_slave_read_req[2]),
        .read_rsp(ixc_slave_read_rsp[2]),
        .write_req(ixc_slave_write_req[2])
    );

endmodule
