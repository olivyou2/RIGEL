module dma_tb ();
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

    dma_ctrl_if #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dma_ctrl ();

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

    rv_if #(
        .ADDR_WIDTH((ADDR_WIDTH)),
        .DATA_WIDTH(1)
    ) dma_dut_read_req ();
    assign read_addr_in = dma_dut_read_req.addr;
    assign read_addr_in_valid = dma_dut_read_req.valid;
    assign dma_dut_read_req.ready = read_addr_in_ready;
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) dma_dut_read_rsp ();
    assign dma_dut_read_rsp.data = read_data_out;
    assign dma_dut_read_rsp.valid = read_data_out_valid;
    assign read_data_out_ready = dma_dut_read_rsp.ready;
    assign dma_dut_read_rsp.addr = '0;
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

    task automatic dma_launch(
        input logic [ADDR_WIDTH-1:0] src_addr, input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [ADDR_WIDTH-1:0] step, input logic [ADDR_WIDTH-1:0] bytes);

        dma_ctrl.valid = 1;
        dma_ctrl.addr_src = src_addr;
        dma_ctrl.addr_dst = dst_addr;
        dma_ctrl.step = step;
        dma_ctrl.length = bytes;

        $display("DMA launch requested. ready=%0d", dma_ctrl.ready);

        while (1) begin
            @(posedge clk);
            if (dma_ctrl.valid && dma_ctrl.ready) begin
                @(negedge clk);
                dma_ctrl.valid = 0;
                $display("DMA launch handshaked");
                break;
            end
        end
    endtask

    task automatic dma_wait();
        logic [31:0] counter = 0;
        do begin
            @(posedge clk);
            counter = counter + 1;
        end while (!dma_ctrl.ready);

        $display("DMA done, consume clocks = %0d", counter);
    endtask

    initial begin
        // testdata
        for (int i = 0; i < 32; i++) begin
            bram_stream_dut.bram_dut.data[i] = 64'hDEAD_BEEF_0000 + i;
        end

        // simulation
        rst_n = 0;
        clk   = 0;
        #10;
        rst_n = 1;
        #10;

        dma_launch(32'h0000_0000, 32'd16376, 8, 16384);
        dma_wait();

        // expect
        for (int i = 0; i < 32; i++) begin
            $display("data[%0h]=%0h, original=%0h", 32'd16384 + i * 8,
                     bram_stream_dut.bram_dut.data[2048+i], bram_stream_dut.bram_dut.data[i]);
        end

        #10;
        $finish();
    end
endmodule
