module dma_addr_src_tb ();

  logic clk;
  logic rst_n;

  always #1 clk = !clk;

  localparam int DATA_WIDTH = 64;
  localparam int ADDR_WIDTH = 32;

  logic addr_rst = 0;
  logic [ADDR_WIDTH-1:0] addr_rst_src;
  logic [ADDR_WIDTH-1:0] addr_rst_step;

  logic fire_in_valid;
  logic fire_in_ready;

  logic [ADDR_WIDTH-1: 0] addr_out;
  logic addr_out_valid;
  logic addr_out_ready;


  dma_src_addr #(
    .ADDR_WIDTH(ADDR_WIDTH /* default 32 */)
   ) dma_addr (
    .clk           (clk),
    .rst_n         (rst_n),
    .addr_rst      (addr_rst),
    .addr_rst_src  (addr_rst_src),
    .addr_rst_step (addr_rst_step),
    
    .fire_in_valid (fire_in_valid),
    .fire_in_ready (fire_in_ready),

    .addr_out      (addr_out),
    .addr_out_valid(addr_out_valid),
    .addr_out_ready(addr_out_ready)
  );

  task automatic set_src_addr(input logic [ADDR_WIDTH-1: 0] addr_src, input logic [ADDR_WIDTH-1: 0] addr_step);
    addr_rst = 1;
    addr_rst_src = addr_src;
    addr_rst_step = addr_step;
    @(posedge clk);
    @(negedge clk);
    addr_rst = 0;
  endtask

  task automatic fire_addr();
    fire_in_valid = 1;
    do begin
        @(posedge clk);
    end while (!fire_in_ready);

    @(negedge clk);
    fire_in_valid = 0;
  endtask

  always @(posedge clk) begin
    if (addr_out_valid && addr_out_ready) begin
      $display("Addr_out=%0h", addr_out);
    end
  end

  initial begin
    clk   = 0;
    rst_n = 0;
    addr_out_ready = 1;

    #10;
    rst_n = 1;
    #10;
    set_src_addr(32'h000010000, 8);

    fire_addr();
    fire_addr();
    addr_out_ready = 0;
    @(posedge clk);
    @(negedge clk);
    addr_out_ready = 1;
    fire_addr();
    fire_addr();
    fire_addr();
    #100;
    $finish();
  end

endmodule

