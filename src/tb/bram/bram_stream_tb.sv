module bram_stream_tb ();

  logic clk;
  logic rst_n;

  always #1 clk = !clk;

  localparam int DATA_WIDTH = 64;
  localparam int ADDR_WIDTH = 32;

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

  bram_stream #(
      .ADDR_WIDTH(ADDR_WIDTH  /* default 32 */),
      .DATA_WIDTH(DATA_WIDTH  /* default 64 */)
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

  task automatic read_request(input logic [ADDR_WIDTH-1:0] addr);
    read_addr_in_valid = 1;
    read_addr_in = addr;

    do begin
      @(posedge clk);
    end while (!read_addr_in_ready);

    // $display("BRAM read requested @ %0h, addr_ready=%0d", addr, read_addr_in_ready);

    @(negedge clk) read_addr_in_valid = 0;
  endtask

  task automatic write_request(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1: 0] data);
    write_data_valid = 1;
    write_data_in = data;
    write_addr_in = addr;

    do begin
      @(posedge clk);
    end while (!write_data_ready);

    @(negedge clk) write_data_valid = 0;
  endtask

  logic [63:0] prev_val = 0;

  always @(posedge clk) begin
    if (read_data_out_valid && read_data_out_ready) begin
        if (prev_val == 0) begin
            prev_val <= read_data_out;
            $display("[BRAM_STREAM_TB] data_out=%0h", read_data_out);
        end else begin
            prev_val <= read_data_out;
            if (read_data_out == prev_val + 1) begin
                $display("[BRAM_STREAM_TB] data_out=%0h", read_data_out);
            end else begin
                $display("[BRAM_STREAM_TB] data_out=%0h, warning: data not success", read_data_out);
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
        read_data_out_ready <= !read_data_out_ready;
        ready_counter <= 0;
    end
  end

  initial begin    
    // Start
    read_data_out_ready = 1;
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