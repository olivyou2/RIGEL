module vector_core#(
    parameter DATA_WIDTH = 8,
    parameter LANE_SIZE = 16
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] lane_in_a[LANE_SIZE],
    input logic [DATA_WIDTH-1: 0] lane_in_b[LANE_SIZE],

    input logic valid,
    output logic ready,

    input logic [4:0] opcode,
    
    output logic [DATA_WIDTH-1: 0] lane_out[LANE_SIZE]
);

    /**
        * ALU Operation *
          Add
          Sub
          Mul
          And
          Or
          Xor
          Shift Left
          Shift Right
          Max
          Min
          Exp
          Sqrt

          * Reduce Operation *
          Max
          Min
          Sum
          Dot
    **/



endmodule