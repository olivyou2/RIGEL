module dma_sge_tb();
    logic clk;
    logic rst_n;

    always #1 clk = !clk;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;

    logic [ADDR_WIDTH-1: 0] read_addr_in;
    logic read_addr_in_valid;
    logic read_addr_in_ready;

    logic [DATA_WIDTH-1: 0] read_data_out;
    logic read_data_out_valid;
    logic read_data_out_ready;

    logic [ADDR_WIDTH-1:0] write_addr_in;
    logic [DATA_WIDTH-1: 0] write_data_in;
    logic write_data_valid;
    logic write_data_ready;

    logic sge_valid = 0;
    logic sge_ready;
    logic [ADDR_WIDTH-1: 0] sge_base_addr;
    logic [5:0] sge_batch_size;

    logic [ADDR_WIDTH*4-1: 0] sge_reg_out;

    logic fire_valid;
    logic fire_ready;
    logic [ADDR_WIDTH-1: 0] fire_length;
    logic [ADDR_WIDTH-1: 0] fire_step;
    logic [ADDR_WIDTH-1: 0] fire_addr_src;
    logic [ADDR_WIDTH-1: 0] fire_addr_dst;
    logic [ADDR_WIDTH*4-1: 0] dma_payload;

    assign fire_length = sge_reg_out    [ADDR_WIDTH-1: 0];
    assign fire_step = sge_reg_out      [ADDR_WIDTH*2-1: ADDR_WIDTH*1];
    assign fire_addr_src = sge_reg_out  [ADDR_WIDTH*3-1: ADDR_WIDTH*2];
    assign fire_addr_dst = sge_reg_out  [ADDR_WIDTH*4-1: ADDR_WIDTH*3];

    function logic[ADDR_WIDTH*4-1: 0] dma_payload_build(
        input logic [ADDR_WIDTH-1: 0] dma_length,
        input logic [ADDR_WIDTH-1: 0] dma_step,
        input logic [ADDR_WIDTH-1: 0] dma_addr_src,
        input logic [ADDR_WIDTH-1: 0] dma_addr_dst
    );

        dma_payload_build[ADDR_WIDTH-1: 0] = dma_length;
        dma_payload_build[ADDR_WIDTH*2-1: ADDR_WIDTH*1] = dma_step;
        dma_payload_build[ADDR_WIDTH*3-1: ADDR_WIDTH*2] = dma_addr_src;
        dma_payload_build[ADDR_WIDTH*4-1: ADDR_WIDTH*3] = dma_addr_dst;
        
    endfunction

    bram_stream #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
    ) bram_stream_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .read_addr_in       (read_addr_in),
        .read_addr_in_valid (read_addr_in_valid),
        .read_addr_in_ready (read_addr_in_ready),
        .read_data_out      (read_data_out),
        .read_data_out_valid(read_data_out_valid),
        .read_data_out_ready(read_data_out_ready),
        .write_addr_in      (write_addr_in),
        .write_data_in      (write_data_in),
        .write_data_valid   (write_data_valid),
        .write_data_ready   (write_data_ready)
    );

    localparam BRAM_ARBITER_N = 2;
    logic [ADDR_WIDTH-1: 0] arbiter_addr_in[BRAM_ARBITER_N];
    logic arbiter_addr_valid[BRAM_ARBITER_N];
    logic arbiter_addr_ready[BRAM_ARBITER_N];

    logic [DATA_WIDTH-1: 0] arbiter_data_out[BRAM_ARBITER_N];
    logic arbiter_data_valid[BRAM_ARBITER_N];
    logic arbiter_data_ready[BRAM_ARBITER_N];


    bram_arbiter #(
        .N         (BRAM_ARBITER_N /* default 4 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */)
     ) bram_arbiter (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr_in       (arbiter_addr_in),
        .addr_valid    (arbiter_addr_valid),
        .addr_ready    (arbiter_addr_ready),
        .data_out      (arbiter_data_out),
        .data_valid    (arbiter_data_valid),
        .data_ready    (arbiter_data_ready),
        .addr_out      (read_addr_in),
        .addr_out_valid(read_addr_in_valid),
        .addr_out_ready(read_addr_in_ready),
        .data_in       (read_data_out),
        .data_in_valid (read_data_out_valid),
        .data_in_ready (read_data_out_ready)
    );

    sge #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .REG_SIZE  (ADDR_WIDTH*4 /* default 128 */),
        .REG_DEPTH (4 /* default 4 */),
        .BATCH_MAX (32 /* default 512 */)
     ) sge (
        .clk           (clk),
        .rst_n         (rst_n),
        .sge_base_addr (sge_base_addr),
        .sge_batch_size(sge_batch_size),
        .sge_valid     (sge_valid),
        .sge_ready     (sge_ready),
        .addr_out      (arbiter_addr_in[1]),
        .addr_valid    (arbiter_addr_valid[1]),
        .addr_ready    (arbiter_addr_ready[1]),
        .data_in       (arbiter_data_out[1]),
        .data_valid    (arbiter_data_valid[1]),
        .data_ready    (arbiter_data_ready[1]),
        .reg_out       (sge_reg_out),
        .reg_valid     (fire_valid),
        .reg_ready     (fire_ready)
    );

    dma #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
    ) dma_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .addr_out          (arbiter_addr_in[0]),
        .addr_out_valid    (arbiter_addr_valid[0]),
        .addr_out_ready    (arbiter_addr_ready[0]),
        .data_in           (arbiter_data_out[0]),
        .data_in_valid     (arbiter_data_valid[0]),
        .data_in_ready     (arbiter_data_ready[0]),
        .dma_addr_out      (write_addr_in),
        .dma_data_out      (write_data_in),
        .dma_data_out_valid(write_data_valid),
        .dma_data_out_ready(write_data_ready),
        .fire_valid        (fire_valid),
        .fire_ready        (fire_ready),
        .fire_length       (fire_length),
        .fire_step         (fire_step),
        .fire_addr_src     (fire_addr_src),
        .fire_addr_dst     (fire_addr_dst)
    );


    
    initial begin
        // testdata
        for (int i=0; i<32; i++) begin
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
        // do @(posedge clk); while (!(fire_valid && fire_ready));
        // do @(posedge clk); while (!fire_ready);

        // expect
        for (int i=0; i<32; i++) begin
            $display("data[%0h]=%0h, original=%0h", 32'd16384+i*8, bram_stream_dut.bram_dut.data[2048+i], bram_stream_dut.bram_dut.data[i]);
        end

        #10;
        $finish();
    end
endmodule
