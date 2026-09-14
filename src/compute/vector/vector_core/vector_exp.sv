// Signed int8 input/output, combinational integer LUT.
// Truncate fractional results; saturate overflow to 127.
module vector_exp#(
    parameter DATA_WIDTH=8,
    parameter LANE_SIZE=16
)(
    input logic [DATA_WIDTH-1: 0] data_in[LANE_SIZE],
    output logic [DATA_WIDTH-1: 0] data_out[LANE_SIZE]
);
    initial begin
        if (DATA_WIDTH != 8)
            $fatal(1, "vector_exp LUT requires signed int8 (DATA_WIDTH=8)");
        if (LANE_SIZE < 1)
            $fatal(1, "LANE_SIZE must be positive");
    end

    // Preserve the bit-vector ports; interpret the input as signed int8
    // in two's complement representation.
    // Constant case table: no runtime arithmetic or real-valued math.
    function automatic logic signed [7:0] exp_lut(input logic signed [7:0] value);
        if (value < 0) begin
            exp_lut = 8'sd0;
        end else begin
            case (value)
                8'sd0: exp_lut = 8'sd1;
                8'sd1: exp_lut = 8'sd2;
                8'sd2: exp_lut = 8'sd7;
                8'sd3: exp_lut = 8'sd20;
                8'sd4: exp_lut = 8'sd54;
                default: exp_lut = 8'sd127; // exp(5) already exceeds int8.
            endcase
        end
    endfunction

    always_comb begin
        for (int i=0; i<LANE_SIZE; i++) begin
            data_out[i] = exp_lut(data_in[i]);
        end
    end
endmodule
