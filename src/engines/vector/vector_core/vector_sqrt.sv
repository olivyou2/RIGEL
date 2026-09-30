// Signed int8 input/output, combinational integer LUT.
// Truncate fractional results; map negative (out-of-domain) inputs to zero.
module vector_sqrt#(
    parameter DATA_WIDTH=8,
    parameter LANE_SIZE=16
)(
    input logic [DATA_WIDTH-1: 0] data_in[LANE_SIZE],
    output logic [DATA_WIDTH-1: 0] data_out[LANE_SIZE]
);
    initial begin
        if (DATA_WIDTH != 8)
            $fatal(1, "vector_sqrt LUT requires signed int8 (DATA_WIDTH=8)");
        if (LANE_SIZE < 1)
            $fatal(1, "LANE_SIZE must be positive");
    end

    // Preserve the bit-vector ports; interpret the input as signed int8
    // in two's complement representation.
    // Constant case table: no runtime arithmetic or real-valued math.
    function automatic logic signed [7:0] sqrt_lut(input logic signed [7:0] value);
        case (value)
            8'sd0: sqrt_lut = 8'sd0;
            8'sd1, 8'sd2, 8'sd3: sqrt_lut = 8'sd1;
            8'sd4, 8'sd5, 8'sd6, 8'sd7, 8'sd8: sqrt_lut = 8'sd2;
            8'sd9, 8'sd10, 8'sd11, 8'sd12, 8'sd13, 8'sd14,
            8'sd15: sqrt_lut = 8'sd3;
            8'sd16, 8'sd17, 8'sd18, 8'sd19, 8'sd20, 8'sd21,
            8'sd22, 8'sd23, 8'sd24: sqrt_lut = 8'sd4;
            8'sd25, 8'sd26, 8'sd27, 8'sd28, 8'sd29, 8'sd30,
            8'sd31, 8'sd32, 8'sd33, 8'sd34, 8'sd35: sqrt_lut = 8'sd5;
            8'sd36, 8'sd37, 8'sd38, 8'sd39, 8'sd40, 8'sd41,
            8'sd42, 8'sd43, 8'sd44, 8'sd45, 8'sd46, 8'sd47,
            8'sd48: sqrt_lut = 8'sd6;
            8'sd49, 8'sd50, 8'sd51, 8'sd52, 8'sd53, 8'sd54,
            8'sd55, 8'sd56, 8'sd57, 8'sd58, 8'sd59, 8'sd60,
            8'sd61, 8'sd62, 8'sd63: sqrt_lut = 8'sd7;
            8'sd64, 8'sd65, 8'sd66, 8'sd67, 8'sd68, 8'sd69,
            8'sd70, 8'sd71, 8'sd72, 8'sd73, 8'sd74, 8'sd75,
            8'sd76, 8'sd77, 8'sd78, 8'sd79, 8'sd80: sqrt_lut = 8'sd8;
            8'sd81, 8'sd82, 8'sd83, 8'sd84, 8'sd85, 8'sd86,
            8'sd87, 8'sd88, 8'sd89, 8'sd90, 8'sd91, 8'sd92,
            8'sd93, 8'sd94, 8'sd95, 8'sd96, 8'sd97, 8'sd98,
            8'sd99: sqrt_lut = 8'sd9;
            8'sd100, 8'sd101, 8'sd102, 8'sd103, 8'sd104, 8'sd105,
            8'sd106, 8'sd107, 8'sd108, 8'sd109, 8'sd110, 8'sd111,
            8'sd112, 8'sd113, 8'sd114, 8'sd115, 8'sd116, 8'sd117,
            8'sd118, 8'sd119, 8'sd120: sqrt_lut = 8'sd10;
            8'sd121, 8'sd122, 8'sd123, 8'sd124, 8'sd125, 8'sd126,
            8'sd127: sqrt_lut = 8'sd11;
            default: sqrt_lut = 8'sd0; // Negative inputs.
        endcase
    endfunction

    always_comb begin
        for (int i=0; i<LANE_SIZE; i++) begin
            data_out[i] = sqrt_lut(data_in[i]);
        end
    end
endmodule
