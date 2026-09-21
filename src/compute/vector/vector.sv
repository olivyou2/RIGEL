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

  rv_if.sink alu_input[3], // write_req_0 = A vector, 1 = B vector, 2 = opcode
  rv_if.source alu_output
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

  rv_if #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) distributed_write_req[2]();

  handshake_distribute #(
    .N(2 /* default 4 */)
   ) handshake_distribute (
    .clk   (clk),
    .rst_n (rst_n),
    .in_ch (alu_input[2]),
    .out_ch(distributed_write_req)
  );

  handshake_addr_join #(
    .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
    .DATA_WIDTH(DATA_WIDTH /* default 64 */)
   ) handshake_addr_join (
    .clk       (clk),
    .rst_n     (rst_n),
    .data_in_ch(bram_data_write_req),
    .addr_in_ch(distributed_write_req[1]),
    .out_ch    (alu_output)
  );

  // Write Vector into ALU
  rv_if #(
    .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
    .DATA_WIDTH(DATA_WIDTH /* default 64 */)
   ) alu_rv_if [3]();

  for (genvar i = 0; i < 2; i++) begin : map_vector_operand
    assign alu_rv_if[i].data = alu_input[i].data;
    assign alu_rv_if[i].addr = alu_input[i].addr;
    assign alu_rv_if[i].valid = alu_input[i].valid;
    assign alu_input[i].ready = alu_rv_if[i].ready;
  end

  assign alu_rv_if[2].data = distributed_write_req[0].data;
  assign alu_rv_if[2].addr = distributed_write_req[0].addr;
  assign alu_rv_if[2].valid = distributed_write_req[0].valid;
  assign distributed_write_req[0].ready = alu_rv_if[2].ready;

  handshake_join #(
    .DATA_WIDTH(DATA_WIDTH /* default 64 */),
    .N         (3 /* default 4 */)
   ) handshake_join (
    .clk   (clk),
    .rst_n (rst_n),
    .in_ch (alu_rv_if),
    .out_ch(alu_write_req)
  );

  vector_alu #(
   ) vector_alu (
    .clk   (clk),
    .rst_n (rst_n),
    .in_ch (alu_write_req),
    .out_ch(bram_data_write_req)
  );

endmodule
