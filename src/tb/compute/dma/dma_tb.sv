module dma_tb();
    logic clk;
    logic rst_n;

    always #1 clk = !clk;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;

    logic [ADDR_WIDTH-1: 0] read_req_addr;
    logic read_req_valid;
    logic read_req_ready;

    logic [DATA_WIDTH-1: 0] read_rsp_data;
    logic read_rsp_valid;
    logic read_rsp_ready;

    logic [ADDR_WIDTH-1:0] write_req_addr;
    logic [DATA_WIDTH-1: 0] write_req_data;
    logic write_req_valid;
    logic write_req_ready;

    logic fire_valid;
    logic fire_ready;
    logic [ADDR_WIDTH-1: 0] fire_length;
    logic [ADDR_WIDTH-1: 0] fire_step;
    logic [ADDR_WIDTH-1: 0] fire_addr_src;
    logic [ADDR_WIDTH-1: 0] fire_addr_dst;

    bram_stream #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
    ) bram_stream_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .read_req_addr       (read_req_addr),
        .read_req_valid (read_req_valid),
        .read_req_ready (read_req_ready),
        .read_rsp_data      (read_rsp_data),
        .read_rsp_valid(read_rsp_valid),
        .read_rsp_ready(read_rsp_ready),
        .write_req_addr      (write_req_addr),
        .write_req_data      (write_req_data),
        .write_req_valid   (write_req_valid),
        .write_req_ready   (write_req_ready)
    );

    dma #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
    ) dma_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .read_req_addr     (read_req_addr),
        .read_req_valid    (read_req_valid),
        .read_req_ready    (read_req_ready),
        .read_rsp_data     (read_rsp_data),
        .read_rsp_valid    (read_rsp_valid),
        .read_rsp_ready    (read_rsp_ready),
        .write_req_addr    (write_req_addr),
        .write_req_data    (write_req_data),
        .write_req_valid   (write_req_valid),
        .write_req_ready   (write_req_ready),
        .fire_valid        (fire_valid),
        .fire_ready        (fire_ready),
        .fire_length       (fire_length),
        .fire_step         (fire_step),
        .fire_addr_src     (fire_addr_src),
        .fire_addr_dst     (fire_addr_dst)
    );

    task automatic dma_launch(
        input logic [ADDR_WIDTH-1: 0] src_addr, 
        input logic [ADDR_WIDTH-1: 0] dst_addr, 
        input logic [ADDR_WIDTH-1: 0] step,
        input logic [ADDR_WIDTH-1: 0] bytes);

        fire_valid = 1;
        fire_addr_src = src_addr;
        fire_addr_dst = dst_addr;
        fire_step = step;
        fire_length = bytes;

        $display("DMA launch requested. ready=%0d", fire_ready);

        while (1) begin
            @(posedge clk);
            if (fire_valid && fire_ready) begin
                @(negedge clk);
                fire_valid = 0;
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
        end while (!fire_ready);

        $display("DMA done, consume clocks = %0d", counter);
    endtask
    
    initial begin
        // testdata
        for (int i=0; i<32; i++) begin
            bram_stream_dut.bram_dut.data[i] = 64'hDEAD_BEEF_0000 + i;
        end

        // simulation
        rst_n = 0;
        clk = 0;
        #10;
        rst_n = 1;
        #10;

        dma_launch(32'h0000_0000, 32'd16376, 8, 16384);
        dma_wait();

        // expect
        for (int i=0; i<32; i++) begin
            $display("data[%0h]=%0h, original=%0h", 32'd16384+i*8, bram_stream_dut.bram_dut.data[2048+i], bram_stream_dut.bram_dut.data[i]);
        end

        #10;
        $finish();
    end
endmodule
