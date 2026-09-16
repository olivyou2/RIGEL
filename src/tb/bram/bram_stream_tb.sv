module bram_stream_tb ();

  logic clk;
  logic rst_n;

  always #1 clk = !clk;

  localparam int DATA_WIDTH = 64;
  localparam int ADDR_WIDTH = 32;

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

  bram_stream #(
      .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
      .DATA_WIDTH(DATA_WIDTH  /* default 64 */)
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

  task automatic read_request(input logic [ADDR_WIDTH-1:0] addr);
    read_req_valid = 1;
    read_req_addr = addr;

    do begin
      @(posedge clk);
    end while (!read_req_ready);

    // $display("BRAM read requested @ %0h, addr_ready=%0d", addr, read_req_ready);

    @(negedge clk) read_req_valid = 0;
  endtask

  task automatic write_request(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1: 0] data);
    write_req_valid = 1;
    write_req_data = data;
    write_req_addr = addr;

    do begin
      @(posedge clk);
    end while (!write_req_ready);

    @(negedge clk) write_req_valid = 0;
  endtask

  logic [63:0] prev_val = 0;

  always @(posedge clk) begin
    if (read_rsp_valid && read_rsp_ready) begin
        if (prev_val == 0) begin
            prev_val <= read_rsp_data;
            $display("[BRAM_STREAM_TB] data_out=%0h", read_rsp_data);
        end else begin
            prev_val <= read_rsp_data;
            if (read_rsp_data == prev_val + 1) begin
                $display("[BRAM_STREAM_TB] data_out=%0h", read_rsp_data);
            end else begin
                $display("[BRAM_STREAM_TB] data_out=%0h, warning: data not success", read_rsp_data);
            end
        end
    end
  end

  logic [3:0] ready_counter;

  initial begin
    ready_counter = 0;
  end

  always @(posedge clk) begin
    ready_counter <= ready_counter + 1;
    if (ready_counter >= 6) begin
        read_rsp_ready <= !read_rsp_ready;
        ready_counter <= 0;
    end
  end

  initial begin    
    // Start
    read_rsp_ready = 1;
    clk   = 0;
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;

    @(negedge clk);

    for (int i=0; i<100; i++) begin
        write_request(i*8, 64'hdead0000 + i);
    end

    for (int i=0; i<100; i++) begin
        read_request(i*8);
    end

    #20;
    $finish;
  end

endmodule
;