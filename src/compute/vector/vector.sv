/**

    Vector Module
        - I/O Processor
          External Interface can access Internal A/B/C Bram
        - Scheduler
          Read data from A/B BRAM, and put it in core. And scheduler transfer Result of core into Scratchpad C
          Scheduler must provide Computing Information such as Accumulate, Operator, and so on
          so scheduler works like Mini Processor, or Command issuer
        - Vector Core
          Vector Core consist with ALU, Reduce Unit (for Reducing Operator such as Softmax) but work in order
        
        - ALU (All the operator can support Accumulate)
          * Multi Lane Out Operators *
          Add
          Sub
          Mul
          And
          Or
          Xor
          Shift
          Max
          Min
          Exp
          Sqrt

          * Single Lane Out Operators *
          Max
          Min
          Sum
          Dot

**/


module vector#(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 128
)(
  input logic clk,
  input logic rst_n,

  rv_if.sink read_req,
  rv_if.source read_rsp,

  rv_if.sink write_req[3], // write_req_0 = A vector, 1 = B vector, 2 = opcode
  rv_if.sink bram_addr_write_req
);

  // Data -> Handshake join -> ALU
  rv_if #(
    .ADDR_WIDTH(1),
    .DATA_WIDTH(DATA_WIDTH * 3)
  ) alu_write_req();

  // Interface -> BRAM
  rv_if #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) bram_read_req();

  rv_if #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) bram_read_rsp();

  // ALU -> BRAM
  rv_if #(
    .ADDR_WIDTH(1),
    .DATA_WIDTH(DATA_WIDTH)
  ) bram_data_write_req();

  rv_if #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) bram_write_req();

  handshake_addr_join #(
    .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
    .DATA_WIDTH(DATA_WIDTH /* default 64 */)
   ) handshake_addr_join (
    .clk       (clk),
    .rst_n     (rst_n),
    .data_in_ch(bram_data_write_req),
    .addr_in_ch(bram_addr_write_req),
    .out_ch    (bram_write_req)
  );

  // Write Vector into ALU
  handshake_join #(
    .DATA_WIDTH(DATA_WIDTH /* default 64 */),
    .N         (3 /* default 4 */)
   ) handshake_join (
    .clk   (clk),
    .rst_n (rst_n),
    .in_ch (write_req),
    .out_ch(alu_write_req)
  );

  vector_core #(
    .DATA_WIDTH(DATA_WIDTH/16 /* default 8 */),
    .LANE_SIZE (16 /* default 16 */)
   ) vector_core (
    .clk   (clk),
    .rst_n (rst_n),
    .in_ch (alu_write_req),
    .out_ch(bram_data_write_req)
  );

  bram_stream #(
    .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
    .DATA_WIDTH(DATA_WIDTH /* default 64 */),
    .DATA_DEPTH(1024 /* default 1024 */)
   ) bram_stream (
    .clk      (clk),
    .rst_n    (rst_n),
    .read_req (read_req),
    .read_rsp (read_rsp),
    .write_req(bram_write_req)
  );


endmodule
