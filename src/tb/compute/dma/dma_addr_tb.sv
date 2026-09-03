module dma_addr_tb ();

  logic clk;
  logic rst_n;


  always #1 clk = !clk;

  localparam int DATA_WIDTH = 64;
  localparam int ADDR_WIDTH = 32;
  
  logic addr_rst = 0;
  logic [ADDR_WIDTH-1:0] addr_rst_dst;
  logic [ADDR_WIDTH-1:0] addr_rst_step;
  logic [DATA_WIDTH-1: 0] data_in;
  logic data_in_valid;
  logic data_in_ready;
  logic [DATA_WIDTH-1: 0] data_out;
  logic [ADDR_WIDTH-1: 0] addr_out;
  logic data_out_valid;
  logic data_out_ready;
  

  dma_dst_addr #(
    .DATA_WIDTH(DATA_WIDTH /* default 64 */),
    .ADDR_WIDTH(ADDR_WIDTH /* default 32 */)
   ) dma_addr (
    .clk           (clk),
    .rst_n         (rst_n),
    .addr_rst      (addr_rst),
    .addr_rst_dst  (addr_rst_dst),
    .addr_rst_step (addr_rst_step),
    .data_in       (data_in),
    .data_in_valid (data_in_valid),
    .data_in_ready (data_in_ready),
    .data_out      (data_out),
    .addr_out      (addr_out),
    .data_out_valid(data_out_valid),
    .data_out_ready(data_out_ready)
  );

  task automatic set_dst_addr(input logic [ADDR_WIDTH-1: 0] addr_dst, input logic [ADDR_WIDTH-1: 0] addr_step);
    addr_rst = 1;
    addr_rst_dst = addr_dst;
    addr_rst_step = addr_step;
    @(posedge clk);
    @(negedge clk);
    addr_rst = 0;
  endtask

  task automatic insert_data(input logic [DATA_WIDTH-1: 0] data);
    data_in_valid = 1;
    data_in = data;
    do begin
        @(posedge clk);
    end while (!data_in_ready);

    @(negedge clk);
    data_in_valid = 0;
  endtask

  always @(posedge clk) begin
    if (data_out_valid && data_out_ready) begin
      $display("Data_out=%0h, Addr_out=%0h", data_out, addr_out);
    end
  end

  initial begin
    clk   = 0;
    rst_n = 0;
    data_out_ready = 1;

    #10;
    rst_n = 1;
    #10;
    set_dst_addr(32'h0000_DDDD, 8);

    insert_data(64'hdeadbeef_deadbeef);
    insert_data(64'hdeadbeef_deadbee2);
    insert_data(64'hdeadbeef_deadbee3);
    #100;
    $finish();
  end

endmodule

