`timescale 1ns/1ps

module compute_tb;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 128;

    logic clk = 0;
    logic rst_n;

    logic [ADDR_WIDTH-1:0] read_addr_in;
    logic read_addr_valid;
    logic read_addr_ready;
    logic [DATA_WIDTH-1:0] read_data_out;
    logic read_data_valid;
    logic read_data_ready;

    logic [ADDR_WIDTH-1:0] write_addr_in;
    logic [DATA_WIDTH-1:0] write_data_in;
    logic write_data_valid;
    logic write_data_ready;

    always #1 clk = ~clk;

    compute #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .read_addr_in(read_addr_in),
        .read_addr_valid(read_addr_valid),
        .read_addr_ready(read_addr_ready),
        .read_data_out(read_data_out),
        .read_data_valid(read_data_valid),
        .read_data_ready(read_data_ready),
        .write_addr_in(write_addr_in),
        .write_data_in(write_data_in),
        .write_data_valid(write_data_valid),
        .write_data_ready(write_data_ready)
    );

    task automatic write_data(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        write_addr_in = addr;
        write_data_in = data;
        write_data_valid = 1;

        do @(posedge clk); while (write_data_ready !== 1'b1);

        @(negedge clk);
        write_data_valid = 0;
    endtask

    // 읽기 주소만 전송하고, 응답 데이터는 아래 always에서 수신
    task automatic read_request(input logic [ADDR_WIDTH-1:0] addr);
        // @(negedge clk);
        read_addr_in = addr;
        read_addr_valid = 1;

        do begin 
            @(posedge clk);
        end while (read_addr_ready !== 1'b1);

        @(negedge clk);
        read_addr_valid = 0;
    endtask

    task automatic read_request_wait(input logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1: 0]data);
        read_request(addr);

        do begin
            @(posedge clk);
        end while (!read_data_valid);

        @(negedge clk);
        data = read_data_out;
    endtask

    task automatic read_request_print(input logic [ADDR_WIDTH-1:0] addr);
        read_request(addr);

        wait (read_data_valid);
        $display("[%0d] read_data = %032h @ %0h", $time, read_data_out, addr);
    endtask

    assign read_data_ready = rst_n;

    always @(posedge clk) begin
        if (rst_n && read_data_valid && read_data_ready) begin
            // $display("[%0d] read_data = %032h", $time, read_data_out);
            // TODO: 수신 데이터 저장 또는 비교
        end
    end

    task automatic run_dma(
        input logic [ADDR_WIDTH-1: 0] src_addr,
        input logic [ADDR_WIDTH-1: 0] dst_addr,
        input logic [ADDR_WIDTH-1: 0] step_size,
        input logic [ADDR_WIDTH-1: 0] length,
        input logic [ADDR_WIDTH-1: 0] dma_idx
    );
        write_data({23'd0, 3'(dma_idx), 3'd0, 3'b0}, length);       // LENGTH
        write_data({23'd0, 3'(dma_idx), 3'd1, 3'b0}, step_size);    // STEP
        write_data({23'd0, 3'(dma_idx), 3'd2, 3'b0}, src_addr);     // SRC
        write_data({23'd0, 3'(dma_idx), 3'd3, 3'b0}, dst_addr);     // DST
        write_data({23'd0, 3'(dma_idx), 3'd4, 3'b0}, 1);            // FIRE

    endtask

    logic dma_ready;

    task automatic run_test();
        // TODO: 테스트 내용 구현 또는 task 호출
        @(negedge clk);
        write_data(32'h0000_1000, 128'hDEADBEEF);
        write_data(32'h0000_1010, {32'hDEADBEEF, 32'h0});
        write_data(32'h0000_1020, {32'hDEADBEEF, 64'h0});
        write_data(32'h0000_1030, {32'hDEADBEEF, 96'h0});
        
        run_dma(32'h0000_1000, 32'h0000_1040, 16, 64, 0);
        run_dma(32'h0000_1000, 32'h0000_1080, 16, 64, 1);
        run_dma(32'h0000_1000, 32'h0000_10B0, 16, 64,2);

        do read_request_wait({23'd0, 3'(0), 3'd5, 3'b0}, dma_ready);
        while (dma_ready == 0);

        do read_request_wait({23'd0, 3'(1), 3'd5, 3'b0}, dma_ready);
        while (dma_ready == 0);

        do read_request_wait({23'd0, 3'(2), 3'd5, 3'b0}, dma_ready);
        while (dma_ready == 0);

        // read_request({23'd0, 3'(0), 3'd5, 3'b0});            // FIRE

        // read_request(32'h0000_1000);
        // read_request(32'h0000_1010);
        // read_request(32'h0000_1020);
        // read_request(32'h0000_1030);
        read_request_print(32'h0000_1040);
        read_request_print(32'h0000_1050);
        read_request_print(32'h0000_1080);
        read_request_print(32'h0000_10B0);

        #1000;
        // 필요한 읽기 응답을 모두 받은 후 task 종료
    endtask

    initial begin
        rst_n = 0;
        read_addr_in = '0;
        read_addr_valid = 0;
        write_addr_in = '0;
        write_data_in = '0;
        write_data_valid = 0;

        repeat (5) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        run_test();

        repeat (5) @(negedge clk);
        $finish;
    end
endmodule
