module vector_alu #(
    parameter DATA_WIDTH = 8,
    parameter RESULT_WIDTH = 8,
    parameter LANE_SIZE  = 16
) (
    input logic clk,
    input logic rst_n,

    // data = {control, packed_C_lanes, packed_B_lanes, packed_A_lanes}.
    // Legacy operations use B/C; FMA uses A + B*C. Lane 0 is LSB.
    rv_if.sink in_ch,

    rv_if.source out_ch,

    output logic done
);
    logic [DATA_WIDTH-1:0] lane_in_a[LANE_SIZE];
    // rv_if ports inherit their width from the connected instance. Verilator
    // uses rv_if's 64-bit default only when vector_alu itself is the lint top,
    // which creates false range/overlap reports for the parameterized slices.
    /* verilator lint_off SELRANGE */
    logic [DATA_WIDTH-1:0] lane_in_b[LANE_SIZE];
    logic [DATA_WIDTH-1:0] lane_in_c[LANE_SIZE];
    for (genvar lane = 0; lane < LANE_SIZE; lane++) begin : map_lane_in
        assign lane_in_a[lane] = in_ch.data[lane*DATA_WIDTH+:DATA_WIDTH];
        assign lane_in_b[lane] =
            in_ch.data[DATA_WIDTH*LANE_SIZE+lane*DATA_WIDTH+:DATA_WIDTH];
        assign lane_in_c[lane] =
            in_ch.data[2*DATA_WIDTH*LANE_SIZE+lane*DATA_WIDTH+:DATA_WIDTH];
    end

    logic lane_sel;
    assign lane_sel = in_ch.data[3*DATA_WIDTH*LANE_SIZE];
    logic [4:0] opcode;
    assign opcode = in_ch.data[3*DATA_WIDTH*LANE_SIZE+1+:5];

    logic valid;
    assign valid = in_ch.valid;
    logic ready;
    assign in_ch.ready = ready;
    logic [RESULT_WIDTH-1:0] lane_out[LANE_SIZE];

    /* verilator lint_off UNUSEDSIGNAL */
    logic [RESULT_WIDTH*LANE_SIZE-1:0] packed_lane_out;
    /* verilator lint_on UNUSEDSIGNAL */
    for (genvar lane = 0; lane < LANE_SIZE; lane++) begin : map_lane_out
        assign packed_lane_out[lane*RESULT_WIDTH+:RESULT_WIDTH] = lane_out[lane];
    end
    // The vector_system uses 16-bit result lanes and a 16-bit raw control.
    // A legacy 128-bit standalone output still receives only packed lanes.
    logic [15:0] control_out, control_skid;
    wire [15:0] incoming_control = 16'(in_ch.data >> (3*DATA_WIDTH*LANE_SIZE));
    assign out_ch.data = $bits(out_ch.data)'({control_out, packed_lane_out});
    /* verilator lint_on SELRANGE */

    logic out_valid;
    assign out_ch.valid = out_valid;
    logic out_ready;
    assign out_ready   = out_ch.ready;
    logic [$bits(out_ch.addr)-1:0] out_addr, skid_addr;
    logic [$bits(out_ch.tag)-1:0] out_tag, skid_tag;
    logic [$bits(out_ch.epoch)-1:0] out_epoch, skid_epoch;
    assign out_ch.addr = out_addr;
    assign out_ch.tag = out_tag;
    assign out_ch.epoch = out_epoch;

    logic [RESULT_WIDTH-1:0] lane_out_skid[LANE_SIZE];
    logic lane_skid_valid;

    logic signed [RESULT_WIDTH-1:0] lane_alu_out[LANE_SIZE];
    logic signed [RESULT_WIDTH-1:0] signed_a[LANE_SIZE];
    logic signed [RESULT_WIDTH-1:0] signed_b[LANE_SIZE];
    logic signed [RESULT_WIDTH-1:0] signed_c[LANE_SIZE];
    for (genvar lane = 0; lane < LANE_SIZE; lane++) begin : widen_operands
        assign signed_a[lane] = $signed(lane_in_a[lane]);
        assign signed_b[lane] = $signed(lane_in_b[lane]);
        assign signed_c[lane] = $signed(lane_in_c[lane]);
    end
    logic [DATA_WIDTH-1:0] lane_exp_out[LANE_SIZE];
    logic [DATA_WIDTH-1:0] lane_sqrt_out[LANE_SIZE];

    localparam [4:0] ALU_ADD = 5'd0;
    localparam [4:0] ALU_SUB = 5'd1;
    localparam [4:0] ALU_MUL = 5'd2;
    localparam [4:0] ALU_AND = 5'd3;
    localparam [4:0] ALU_OR = 5'd4;
    localparam [4:0] ALU_XOR = 5'd5;
    localparam [4:0] ALU_LS = 5'd6;
    localparam [4:0] ALU_RS = 5'd7;
    localparam [4:0] ALU_MAX = 5'd8;
    localparam [4:0] ALU_MIN = 5'd9;
    localparam [4:0] ALU_EXP = 5'd10;
    localparam [4:0] ALU_SQRT = 5'd11;
    localparam [4:0] ALU_FMA = 5'd12;

    logic [DATA_WIDTH-1:0] lane_unary_in[LANE_SIZE];

    vector_exp #(
        .DATA_WIDTH(DATA_WIDTH  /* default 8 */),
        .LANE_SIZE (LANE_SIZE  /* default 16 */)
    ) vector_exp (
        .data_in (lane_unary_in),
        .data_out(lane_exp_out)
    );

    vector_sqrt #(
        .DATA_WIDTH(DATA_WIDTH  /* default 8 */),
        .LANE_SIZE (LANE_SIZE  /* default 16 */)
    ) vector_sqrt (
        .data_in (lane_unary_in),
        .data_out(lane_sqrt_out)
    );

    // Select per lane to keep unpacked-array port connections tool-compatible.
    for (genvar lane = 0; lane < LANE_SIZE; lane++) begin : unary_input
        assign lane_unary_in[lane] = lane_sel ? lane_in_c[lane] : lane_in_b[lane];
    end

    // Signed arithmetic uses RESULT_WIDTH bits; in vector_system it preserves
    // the full signed int8 product (16 bits). Legacy operations use B/C.
    logic lane_b_bigger[LANE_SIZE];

    always_comb begin
        for (int i = 0; i < LANE_SIZE; i++) begin
            lane_b_bigger[i] = $signed(lane_in_b[i]) > $signed(lane_in_c[i]);

            case (opcode)
                ALU_ADD:  lane_alu_out[i] = signed_b[i] + signed_c[i];
                ALU_SUB:  lane_alu_out[i] = signed_b[i] - signed_c[i];
                ALU_MUL:  lane_alu_out[i] = signed_b[i] * signed_c[i];
                ALU_AND:  lane_alu_out[i] = signed_b[i] & signed_c[i];
                ALU_OR:   lane_alu_out[i] = signed_b[i] | signed_c[i];
                ALU_XOR:  lane_alu_out[i] = signed_b[i] ^ signed_c[i];
                ALU_LS:   lane_alu_out[i] = signed_b[i] << lane_in_c[i];
                ALU_RS:   lane_alu_out[i] = signed_b[i] >>> lane_in_c[i];
                ALU_MAX:  lane_alu_out[i] = lane_b_bigger[i] ? signed_b[i] : signed_c[i];
                ALU_MIN:  lane_alu_out[i] = lane_b_bigger[i] ? signed_c[i] : signed_b[i];
                ALU_EXP:  lane_alu_out[i] = lane_exp_out[i];
                ALU_SQRT: lane_alu_out[i] = lane_sqrt_out[i];
                ALU_FMA:  lane_alu_out[i] = signed_a[i] + signed_b[i] * signed_c[i];

                default: lane_alu_out[i] = 0;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 0;
            ready <= 1;
            done <= 0;
            lane_skid_valid <= 0;
            control_out <= '0;
            control_skid <= '0;

            for (int i = 0; i < LANE_SIZE; i++) begin
                lane_out[i] <= 0;
                lane_out_skid[i] <= 0;
            end
        end else begin
            done <= 0;

            if (out_valid && out_ready) begin
                if (lane_skid_valid) begin
                    done <= 1;
                    lane_skid_valid <= 0;
                    ready <= 1;
                    out_addr <= skid_addr;
                    out_tag <= skid_tag;
                    out_epoch <= skid_epoch;
                    control_out <= control_skid;

                    for (int i = 0; i < LANE_SIZE; i++) begin
                        lane_out[i] <= lane_out_skid[i];
                    end
                end else begin
                    out_valid <= 0;
                end
            end

            if (valid && ready) begin
                // for (int i=0; i<16; i++) begin
                //     $display("[ALU] lane_Id=%0d, lane A=%0x, lane B=%0x, lane Out=%0x", i, lane_in_a[i], lane_in_b[i], lane_alu_out[i]);
                // end
                for (int i = 0; i < LANE_SIZE; i++) begin
                    if (!out_valid || (out_valid && out_ready)) begin
                        out_valid   <= 1;
                        done <= 1;
                        lane_out[i] <= lane_alu_out[i];
                        out_addr <= in_ch.addr;
                        out_tag <= in_ch.tag;
                        out_epoch <= in_ch.epoch;
                        control_out <= incoming_control;
                    end else begin
                        lane_out_skid[i] <= lane_alu_out[i];
                        lane_skid_valid <= 1;
                        ready <= 0;
                        skid_addr <= in_ch.addr;
                        skid_tag <= in_ch.tag;
                        skid_epoch <= in_ch.epoch;
                        control_skid <= incoming_control;
                    end
                end
            end
        end
    end

endmodule
