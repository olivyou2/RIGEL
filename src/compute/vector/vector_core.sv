module vector_core#(
    parameter DATA_WIDTH = 8,
    parameter LANE_SIZE = 16
)(
    input logic clk,
    input logic rst_n,

    rv_if.sink in_ch,
    rv_if.source out_ch
);

    vector_alu #(
        .DATA_WIDTH(DATA_WIDTH /* default 8 */),
        .LANE_SIZE (LANE_SIZE /* default 16 */)
     ) vector_alu (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (in_ch),
        .out_ch(out_ch)
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