`timescale 1ns/1ps

module compute_tb;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 128;
    localparam DMA_INDEX = 0;
    localparam DMA_BYTES = 2048;

    longint unsigned cycle_count = 0;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    logic clk = 0;
    logic rst_n;

    logic [ADDR_WIDTH-1:0] read_req_addr;
    logic read_req_valid;
    logic read_req_ready;
    logic [DATA_WIDTH-1:0] read_rsp_data;
    logic read_rsp_valid;
    logic read_rsp_ready;

    logic [ADDR_WIDTH-1:0] write_req_addr;
    logic [DATA_WIDTH-1:0] write_req_data;
    logic write_req_valid;
    logic write_req_ready;

    always #1 clk = ~clk;

    compute #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .read_req_addr(read_req_addr),
        .read_req_valid(read_req_valid),
        .read_req_ready(read_req_ready),
        .read_rsp_data(read_rsp_data),
        .read_rsp_valid(read_rsp_valid),
        .read_rsp_ready(read_rsp_ready),
        .write_req_addr(write_req_addr),
        .write_req_data(write_req_data),
        .write_req_valid(write_req_valid),
        .write_req_ready(write_req_ready)
    );

    task automatic write_data(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        write_req_addr = addr;
        write_req_data = data;
        write_req_valid = 1;

        do @(posedge clk); while (write_req_ready !== 1'b1);

        @(negedge clk);
        write_req_valid = 0;
    endtask

    // 읽기 주소만 전송하고, 응답 데이터는 아래 always에서 수신
    task automatic read_request(input logic [ADDR_WIDTH-1:0] addr);
        // @(negedge clk);
        read_req_addr = addr;
        read_req_valid = 1;

        do begin 
            @(posedge clk);
        end while (read_req_ready !== 1'b1);

        @(negedge clk);
        read_req_valid = 0;
    endtask

    task automatic read_request_wait(input logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1: 0]data);
        read_request(addr);

        do begin
            @(posedge clk);
        end while (!(read_rsp_valid && read_rsp_ready));

        // FIFO가 pop되는 posedge에서 현재 응답을 먼저 저장
        data = read_rsp_data;
        @(negedge clk);
    endtask

    task automatic read_request_print(input logic [ADDR_WIDTH-1:0] addr);
        logic [DATA_WIDTH-1:0] data;
        read_request_wait(addr, data);
        $display("[%0d] read_data = %032h @ %0h", $time, data, addr);
    endtask

    assign read_rsp_ready = rst_n;

    always @(posedge clk) begin
        if (rst_n && read_rsp_valid && read_rsp_ready) begin
            // $display("[%0d] read_data = %032h", $time, read_rsp_data);
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

        // IXC가 FIRE 쓰기를 버퍼링하므로 실제 DMA 시작까지 기다림
        do @(posedge clk);
        while (!(dut.dma_fire_valid[dma_idx] && dut.dma_fire_ready[dma_idx]));
        @(negedge clk);

    endtask

    logic [DATA_WIDTH-1:0] dma_status;
    longint unsigned timer_t;

    task automatic run_test();
        // TODO: 테스트 내용 구현 또는 task 호출
        @(negedge clk);
        write_data(32'h0000_1000, 128'hDEADBEEF);
        write_data(32'h0000_1010, {32'hDEADBEEF, 32'h0});
        write_data(32'h0000_1020, {32'hDEADBEEF, 64'h0});
        write_data(32'h0000_1030, {32'hDEADBEEF, 96'h0});
        
        // 설정 전부터 완료 확인까지 측정: 설정/상태 폴링 지연 포함
        timer_t = cycle_count;
        run_dma(32'h0000_1000, 32'h0000_5000, DATA_WIDTH/8, DMA_BYTES, DMA_INDEX);
        
        do read_request_wait({23'd0, 3'(DMA_INDEX), 3'd5, 3'b0}, dma_status);
        while (dma_status[0] !== 1'b1);
        
        timer_t = cycle_count - timer_t;

        $display("DMA Transfer rate (setup + polling) = %0.3f bytes/clock (%0d bytes / %0d clocks)",
                 real'(DMA_BYTES) / real'(timer_t), DMA_BYTES, timer_t);

        // read_request({23'd0, 3'(0), 3'd5, 3'b0});            // FIRE

        // read_request(32'h0000_1000);
        // read_request(32'h0000_1010);
        // read_request(32'h0000_1020);
        // read_request(32'h0000_1030);
        read_request_print(32'h0000_5000);
        read_request_print(32'h0000_5010);
        read_request_print(32'h0000_5020);
        read_request_print(32'h0000_5030);

        #1000;
        // 필요한 읽기 응답을 모두 받은 후 task 종료
    endtask

    initial begin
        rst_n = 0;
        read_req_addr = '0;
        read_req_valid = 0;
        write_req_addr = '0;
        write_req_data = '0;
        write_req_valid = 0;

        repeat (5) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        run_test();

        repeat (5) @(negedge clk);
        $finish;
    end
endmodule
