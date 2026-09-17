module dma_sge_tb ();
    logic clk;
    logic rst_n;

    always #1 clk = !clk;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;

    logic [ADDR_WIDTH-1:0] read_addr_in;
    logic read_addr_in_valid;
    logic read_addr_in_ready;

    logic [DATA_WIDTH-1:0] read_data_out;
    logic read_data_out_valid;
    logic read_data_out_ready;

    logic [ADDR_WIDTH-1:0] write_addr_in;
    logic [DATA_WIDTH-1:0] write_data_in;
    logic write_data_valid;
    logic write_data_ready;

    logic sge_valid = 0;
    logic sge_ready;
    logic [ADDR_WIDTH-1:0] sge_base_addr;
    logic [5:0] sge_batch_size;

    logic [ADDR_WIDTH*4-1:0] sge_reg_out;

    dma_ctrl_if #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dma_ctrl ();
    logic [ADDR_WIDTH*4-1:0] dma_payload;

    assign dma_ctrl.length   = sge_reg_out[ADDR_WIDTH-1:0];
    assign dma_ctrl.step     = sge_reg_out[ADDR_WIDTH*2-1:ADDR_WIDTH*1];
    assign dma_ctrl.addr_src = sge_reg_out[ADDR_WIDTH*3-1:ADDR_WIDTH*2];
    assign dma_ctrl.addr_dst = sge_reg_out[ADDR_WIDTH*4-1:ADDR_WIDTH*3];

    function logic [ADDR_WIDTH*4-1:0] dma_payload_build(
        input logic [ADDR_WIDTH-1:0] dma_length, input logic [ADDR_WIDTH-1:0] dma_step,
        input logic [ADDR_WIDTH-1:0] dma_addr_src, input logic [ADDR_WIDTH-1:0] dma_addr_dst);

        dma_payload_build[ADDR_WIDTH-1:0] = dma_length;
        dma_payload_build[ADDR_WIDTH*2-1:ADDR_WIDTH*1] = dma_step;
        dma_payload_build[ADDR_WIDTH*3-1:ADDR_WIDTH*2] = dma_addr_src;
        dma_payload_build[ADDR_WIDTH*4-1:ADDR_WIDTH*3] = dma_addr_dst;

    endfunction

    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH(1)
    ) bram_stream_dut_read_req ();
    assign bram_stream_dut_read_req.addr = read_addr_in;
    assign bram_stream_dut_read_req.valid = read_addr_in_valid;
    assign read_addr_in_ready = bram_stream_dut_read_req.ready;
    assign bram_stream_dut_read_req.data = '0;
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) bram_stream_dut_read_rsp ();
    assign read_data_out = bram_stream_dut_read_rsp.data;
    assign read_data_out_valid = bram_stream_dut_read_rsp.valid;
    assign bram_stream_dut_read_rsp.ready = read_data_out_ready;
    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH((DATA_WIDTH))
    ) bram_stream_dut_write_req ();
    assign bram_stream_dut_write_req.addr = write_addr_in;
    assign bram_stream_dut_write_req.data = write_data_in;
    assign bram_stream_dut_write_req.valid = write_data_valid;
    assign write_data_ready = bram_stream_dut_write_req.ready;
    bram_stream #(
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */)
    ) bram_stream_dut (
        .clk(clk),
        .rst_n(rst_n),
        .read_req(bram_stream_dut_read_req),
        .read_rsp(bram_stream_dut_read_rsp),
        .write_req(bram_stream_dut_write_req)
    );

    localparam BRAM_ARBITER_N = 2;
    logic [ADDR_WIDTH-1:0] arbiter_addr_in[BRAM_ARBITER_N];
    logic arbiter_addr_valid[BRAM_ARBITER_N];
    logic arbiter_addr_ready[BRAM_ARBITER_N];

    logic [DATA_WIDTH-1:0] arbiter_data_out[BRAM_ARBITER_N];
    logic arbiter_data_valid[BRAM_ARBITER_N];
    logic arbiter_data_ready[BRAM_ARBITER_N];

    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH(1)
    ) bram_arbiter_read_req[(BRAM_ARBITER_N)] ();
    for (
        genvar ch_idx = 0; ch_idx < (BRAM_ARBITER_N); ch_idx++
    ) begin : connect_bram_arbiter_read_req
        assign bram_arbiter_read_req[ch_idx].addr = arbiter_addr_in[ch_idx];
        assign bram_arbiter_read_req[ch_idx].valid = arbiter_addr_valid[ch_idx];
        assign arbiter_addr_ready[ch_idx] = bram_arbiter_read_req[ch_idx].ready;
        assign bram_arbiter_read_req[ch_idx].data = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) bram_arbiter_read_rsp[(BRAM_ARBITER_N)] ();
    for (
        genvar ch_idx = 0; ch_idx < (BRAM_ARBITER_N); ch_idx++
    ) begin : connect_bram_arbiter_read_rsp
        assign arbiter_data_out[ch_idx] = bram_arbiter_read_rsp[ch_idx].data;
        assign arbiter_data_valid[ch_idx] = bram_arbiter_read_rsp[ch_idx].valid;
        assign bram_arbiter_read_rsp[ch_idx].ready = arbiter_data_ready[ch_idx];
    end
    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH(1)
    ) bram_arbiter_slave_read_req ();
    assign read_addr_in = bram_arbiter_slave_read_req.addr;
    assign read_addr_in_valid = bram_arbiter_slave_read_req.valid;
    assign bram_arbiter_slave_read_req.ready = read_addr_in_ready;
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) bram_arbiter_slave_read_rsp ();
    assign bram_arbiter_slave_read_rsp.data = read_data_out;
    assign bram_arbiter_slave_read_rsp.valid = read_data_out_valid;
    assign read_data_out_ready = bram_arbiter_slave_read_rsp.ready;
    assign bram_arbiter_slave_read_rsp.addr = '0;
    bram_arbiter #(
        .N         (BRAM_ARBITER_N  /* default 4 */),
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */)
    ) bram_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .read_req(bram_arbiter_read_req),
        .read_rsp(bram_arbiter_read_rsp),
        .slave_read_req(bram_arbiter_slave_read_req),
        .slave_read_rsp(bram_arbiter_slave_read_rsp)
    );

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) sge_data_ch ();
    assign sge_data_ch.data = arbiter_data_out[1];
    assign sge_data_ch.valid = arbiter_data_valid[1];
    assign arbiter_data_ready[1] = sge_data_ch.ready;
    assign sge_data_ch.addr = '0;
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((ADDR_WIDTH * 4))
    ) sge_reg_ch ();
    assign sge_reg_out = sge_reg_ch.data;
    assign dma_ctrl.valid = sge_reg_ch.valid;
    assign sge_reg_ch.ready = dma_ctrl.ready;
    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH(1)
    ) sge_read_req ();
    assign arbiter_addr_in[1] = sge_read_req.addr;
    assign arbiter_addr_valid[1] = sge_read_req.valid;
    assign sge_read_req.ready = arbiter_addr_ready[1];
    sge #(
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .REG_SIZE  (ADDR_WIDTH * 4  /* default 128 */),
        .REG_DEPTH (4  /* default 4 */),
        .BATCH_MAX (32  /* default 512 */)
    ) sge (
        .clk(clk),
        .rst_n(rst_n),
        .sge_base_addr(sge_base_addr),
        .sge_batch_size(sge_batch_size),
        .sge_valid(sge_valid),
        .sge_ready(sge_ready),
        .data_ch(sge_data_ch),
        .reg_ch(sge_reg_ch),
        .read_req(sge_read_req)
    );

    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH(1)
    ) dma_dut_read_req ();
    assign arbiter_addr_in[0] = dma_dut_read_req.addr;
    assign arbiter_addr_valid[0] = dma_dut_read_req.valid;
    assign dma_dut_read_req.ready = arbiter_addr_ready[0];
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) dma_dut_read_rsp ();
    assign dma_dut_read_rsp.data  = arbiter_data_out[0];
    assign dma_dut_read_rsp.valid = arbiter_data_valid[0];
    assign arbiter_data_ready[0]  = dma_dut_read_rsp.ready;
    assign dma_dut_read_rsp.addr  = '0;
    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH((DATA_WIDTH))
    ) dma_dut_write_req ();
    assign write_addr_in = dma_dut_write_req.addr;
    assign write_data_in = dma_dut_write_req.data;
    assign write_data_valid = dma_dut_write_req.valid;
    assign dma_dut_write_req.ready = write_data_ready;
    dma #(
        .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */)
    ) dma_dut (
        .clk(clk),
        .rst_n(rst_n),
        .ctrl(dma_ctrl),
        .read_req(dma_dut_read_req),
        .read_rsp(dma_dut_read_rsp),
        .write_req(dma_dut_write_req)
    );

    initial begin
        // testdata
        for (int i = 0; i < 32; i++) begin
            bram_stream_dut.bram_dut.data[i] = 64'hDEAD_BEEF_0000 + i;
        end

        dma_payload = dma_payload_build(32'd64, 32'd8, 32'd32, 32'd16384);
        bram_stream_dut.bram_dut.data[0] = dma_payload[DATA_WIDTH-1:0];
        bram_stream_dut.bram_dut.data[1] = dma_payload[DATA_WIDTH*2-1:DATA_WIDTH];

        dma_payload = dma_payload_build(32'd64, 32'd8, 32'd32 + 128, 32'd16384 + 64);
        bram_stream_dut.bram_dut.data[2] = dma_payload[DATA_WIDTH-1:0];
        bram_stream_dut.bram_dut.data[3] = dma_payload[DATA_WIDTH*2-1:DATA_WIDTH];

        // simulation
        rst_n = 0;
        clk = 0;
        #10;
        rst_n = 1;
        #10;

        sge_base_addr = 0;
        sge_batch_size = 2;
        sge_valid = 1;
        do @(posedge clk); while (!sge_ready);
        @(negedge clk);
        sge_valid = 0;

        do @(posedge clk); while (!sge_ready);
        // do @(posedge clk); while (!(dma_ctrl.valid && dma_ctrl.ready));
        // do @(posedge clk); while (!dma_ctrl.ready);

        // expect
        for (int i = 0; i < 32; i++) begin
            $display("data[%0h]=%0h, original=%0h", 32'd16384 + i * 8,
                     bram_stream_dut.bram_dut.data[2048+i], bram_stream_dut.bram_dut.data[i]);
        end

        #10;
        $finish();
    end
endmodule
