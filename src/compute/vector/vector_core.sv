module vector_core#(
    parameter DATA_WIDTH = 8,
    parameter LANE_SIZE = 16
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] lane_in_a[LANE_SIZE],
    input logic [DATA_WIDTH-1: 0] lane_in_b[LANE_SIZE],
    input logic lane_sel,

    input logic valid,
    output logic ready,

    input logic [4:0] opcode,
    
    output logic [DATA_WIDTH-1: 0] lane_out[LANE_SIZE],
    output logic lane_out_valid,
    input logic lane_out_ready
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

    vector_alu #(
        .DATA_WIDTH(DATA_WIDTH /* default 8 */),
        .LANE_SIZE (LANE_SIZE /* default 16 */)
     ) vector_alu (
        .clk      (clk),
        .rst_n    (rst_n),
        .lane_in_a(lane_in_a),
        .lane_in_b(lane_in_b),
        .lane_sel (lane_sel),
        .opcode   (opcode),
        .valid    (valid),
        .ready    (ready),
        .lane_out (lane_out),
        .out_valid(lane_out_valid),
        .out_ready(lane_out_ready)
    );


endmodule