module compute_tb();
    logic clk = 0;
    logic rst_n = 0;

    always #1 clk = !clk;
    
    localparam X_BITS = 2;
    localparam Y_BITS = 2;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;

    localparam PAYLOAD_ADDR_SIZE = ADDR_WIDTH - X_BITS - Y_BITS;

    logic [ADDR_WIDTH-1: 0] addr_in;
    logic [DATA_WIDTH-1: 0] data_in;
    logic in_valid;
    logic in_ready;

    logic [ADDR_WIDTH-1: 0] addr_out;
    logic [DATA_WIDTH-1: 0] data_out;
    logic out_valid;
    logic out_ready;

    always @(posedge clk) begin
        out_ready <= 1;
        if (out_valid && out_ready) begin
            logic [1:0] dst_x;
            logic [1:0] dst_y;

            dst_x = addr_out[ADDR_WIDTH-1 -: X_BITS];
            dst_y = addr_out[ADDR_WIDTH-1-X_BITS -: Y_BITS];

            $display("[%0d] Pakcet arrival: dst_x=%0d, dst_y=%0d, addr=%08h, data=%0h", $time(), dst_x, dst_y, addr_out[PAYLOAD_ADDR_SIZE-1: 0], data_out);
        end
    end

    task automatic write_value(logic [ADDR_WIDTH-1: 0] addr, logic [DATA_WIDTH-1: 0] data);
        addr_in = addr;
        data_in = data;
        in_valid = 1;

        do begin
            // $display("Wait for in_ready rise..");
            @(posedge clk);
        end while(!in_ready);

        // $display("Write done");

        @(negedge clk);
        in_valid = 0;
    endtask

    compute #(
        .X_BITS    (X_BITS /* default 2 */),
        .Y_BITS    (Y_BITS /* default 2 */),
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) compute (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr_in  (addr_in),
        .data_in  (data_in),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .addr_out (addr_out),
        .data_out (data_out),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    localparam [PAYLOAD_ADDR_SIZE-1:0] REQ_GRANT = 'h0;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_LENGTH = 'h8;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_STEP = 'h10;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_ADDR_SRC = 'h18;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_ADDR_DST = 'h20;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_FIRE = 'h28;

    initial begin
        for (int i=0; i<128; i++) begin
            compute.bram_stream.bram_dut.data[i] = i*10;
        end

        rst_n = 0;
        #10;
        rst_n = 1;
        #10;

        write_value(DMA_LENGTH,64'd1024);
        write_value(DMA_STEP,64'h8);
        write_value(DMA_ADDR_SRC,64'h8);
        write_value(DMA_ADDR_DST,64'h20);
        write_value(DMA_FIRE,1);

        #50;
        write_value(REQ_GRANT,0); // Request Grant

        #1000;
        $finish();
    end
endmodule;