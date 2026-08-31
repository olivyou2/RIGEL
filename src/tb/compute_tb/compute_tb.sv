module compute_tb();

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 64;

    parameter BRAM_DATA_DEPTH = 4096;
    parameter BRAM_ADDR_WORD_WIDTH = $clog2(BRAM_DATA_DEPTH);

    logic clk = 0;
    logic rst_n = 0;

    logic [ADDR_WIDTH-1: 0] addr_in = 0;
    logic [DATA_WIDTH-1: 0] data_in = 0;
    logic in_valid = 0;
    logic in_ready = 0;
    
    logic [ADDR_WIDTH-1: 0] addr_out = 0;
    logic [DATA_WIDTH-1: 0] data_out = 0;
    logic out_valid = 0;
    logic out_ready = 0;

    compute compute_dut(
        .clk(clk),
        .rst_n(rst_n),
        .addr_in(addr_in),
        .data_in(data_in),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .addr_out(addr_out),
        .data_out(data_out),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    task automatic spad_assert_a(logic [DATA_WIDTH-1:0] expect_data, logic [BRAM_ADDR_WORD_WIDTH-1:0] word_addr);
        if (compute_dut.scratchpad_a.data[word_addr] != expect_data) begin
            $display("[FATAL] scratchpad_a data missmatch @ %0d, Expect=%x, Actual=%x", word_addr, expect_data, compute_dut.scratchpad_a.data[word_addr]);
            $finish;
        end else begin
            $display("[OKAY] scratchpad_a data matched, Expect=%x, Actual=%x", expect_data, compute_dut.scratchpad_a.data[word_addr]);
        end
    endtask

    task automatic spad_assert_b(logic [DATA_WIDTH-1:0] expect_data, logic [BRAM_ADDR_WORD_WIDTH-1:0] word_addr);
        if (compute_dut.scratchpad_b.data[word_addr] != expect_data) begin
            $display("[FATAL] scratchpad_b data missmatch @ %0d, Expect=%x, Actual=%x", word_addr, expect_data, compute_dut.scratchpad_b.data[word_addr]);
            $finish;
        end else begin
            $display("[OKAY] scratchpad_b data matched, Expect=%x, Actual=%x", expect_data, compute_dut.scratchpad_b.data[word_addr]);
        end
    endtask
    
    // Use this task at Falling edge
    task automatic write_data(logic [ADDR_WIDTH-1:0] addr, logic [DATA_WIDTH-1:0] data);
        addr_in = addr;
        data_in = data;
        in_valid = 1;
        
        @(posedge clk);
        @(negedge clk);

        in_valid = 0;
    endtask

    task automatic tick();
        @(posedge clk);
        @(negedge clk);

    endtask

    always #1 clk = !clk;

    localparam SPAD_SIZE = 16'h7FFF;
    localparam SPAD_A_BASE_ADDR = 32'h0000_0000;
    localparam SPAD_B_BASE_ADDR = 32'h0001_0000;

    localparam DMA_BASE_ADDR = 32'h0003_0000;

    localparam DMA_SRC  = 32'h00;
    localparam DMA_DST  = 32'h08;
    localparam DMA_LEN  = 32'h10;
    localparam DMA_FIRE = 32'hF8;

    initial begin
        rst_n = 0;
        #100;
        
        rst_n = 1;
        #100;

        @(negedge clk);        

        // Scratchpad A Region test
        for (int i=0; i<SPAD_SIZE; i+=8) begin
            write_data(SPAD_A_BASE_ADDR + i, 64'(i+i));
        end
        tick();
        for (int i=0; i<SPAD_SIZE; i+=8) begin
            spad_assert_a(64'(i+i), i/8);
        end
        $display("[OKAY] scratchpad A region test pass");

        // Scratchpad B Region test
        for (int i=0; i<SPAD_SIZE; i+=8) begin
            write_data(SPAD_B_BASE_ADDR + i, 64'(i*2-4));
        end
        tick();
        for (int i=0; i<SPAD_SIZE; i+=8) begin
            spad_assert_b(64'(i*2-4), i/8);
        end
        $display("[OKAY] scratchpad B region test pass");
        
        // DMA Fire test
        write_data(DMA_BASE_ADDR + DMA_SRC, 64'h0002_0000);
        write_data(DMA_BASE_ADDR + DMA_DST, 64'h1100_0000);
        write_data(DMA_BASE_ADDR + DMA_LEN, 64); // Total 64 bytes
        write_data(DMA_BASE_ADDR + DMA_FIRE, 1); // Fire

        $finish;
    end

endmodule;