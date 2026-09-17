module vector_alu #(
    parameter DATA_WIDTH = 8,
    parameter LANE_SIZE  = 16
) (
    input logic clk,
    input logic rst_n,

    // data = {opcode[4:0], lane_sel, packed_B_lanes, packed_A_lanes}; lane 0 is LSB.
    rv_if.sink in_ch,

    rv_if.source out_ch
);
    logic [DATA_WIDTH-1:0] lane_in_a[LANE_SIZE];
    // rv_if ports inherit their width from the connected instance. Verilator
    // uses rv_if's 64-bit default only when vector_alu itself is the lint top,
    // which creates false range/overlap reports for the parameterized slices.
    /* verilator lint_off SELRANGE */
    logic [DATA_WIDTH-1:0] lane_in_b[LANE_SIZE];
    for (genvar lane = 0; lane < LANE_SIZE; lane++) begin : map_lane_in
        assign lane_in_a[lane] = in_ch.data[lane*DATA_WIDTH+:DATA_WIDTH];
        assign lane_in_b[lane] =
            in_ch.data[DATA_WIDTH*LANE_SIZE+lane*DATA_WIDTH+:DATA_WIDTH];
    end

    logic lane_sel;
    assign lane_sel = in_ch.data[2*DATA_WIDTH*LANE_SIZE];
    logic [4:0] opcode;
    assign opcode = in_ch.data[2*DATA_WIDTH*LANE_SIZE+1+:5];

    logic valid;
    assign valid = in_ch.valid;
    logic ready;
    assign in_ch.ready = ready;
    logic [DATA_WIDTH-1:0] lane_out[LANE_SIZE];

    /* verilator lint_off UNUSEDSIGNAL */
    logic [DATA_WIDTH*LANE_SIZE-1:0] packed_lane_out;
    /* verilator lint_on UNUSEDSIGNAL */
    for (genvar lane = 0; lane < LANE_SIZE; lane++) begin : map_lane_out
        assign packed_lane_out[lane*DATA_WIDTH+:DATA_WIDTH] = lane_out[lane];
    end
    assign out_ch.data = $bits(out_ch.data)'(packed_lane_out);
    /* verilator lint_on SELRANGE */

    logic out_valid;
    assign out_ch.valid = out_valid;
    logic out_ready;
    assign out_ready   = out_ch.ready;
    assign out_ch.addr = in_ch.addr;

    logic [DATA_WIDTH-1:0] lane_out_skid[LANE_SIZE];
    logic lane_skid_valid;

    logic [DATA_WIDTH-1:0] lane_alu_out[LANE_SIZE];
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
        assign lane_unary_in[lane] = lane_sel ? lane_in_b[lane] : lane_in_a[lane];
    end

    // Signed int8 arithmetic; ADD/SUB/MUL wrap to the low DATA_WIDTH bits.
    // Shift counts are unsigned bit counts. Right shift sign-extends A.
    logic lane_a_bigger[LANE_SIZE];

    always_comb begin
        for (int i = 0; i < LANE_SIZE; i++) begin
            lane_a_bigger[i] = $signed(lane_in_a[i]) > $signed(lane_in_b[i]);

            case (opcode)
                ALU_ADD:  lane_alu_out[i] = lane_in_a[i] + lane_in_b[i];
                ALU_SUB:  lane_alu_out[i] = lane_in_a[i] - lane_in_b[i];
                ALU_MUL:  lane_alu_out[i] = lane_in_a[i] * lane_in_b[i];
                ALU_AND:  lane_alu_out[i] = lane_in_a[i] & lane_in_b[i];
                ALU_OR:   lane_alu_out[i] = lane_in_a[i] | lane_in_b[i];
                ALU_XOR:  lane_alu_out[i] = lane_in_a[i] ^ lane_in_b[i];
                ALU_LS:   lane_alu_out[i] = lane_in_a[i] << lane_in_b[i];
                ALU_RS:   lane_alu_out[i] = $signed(lane_in_a[i]) >>> lane_in_b[i];
                ALU_MAX:  lane_alu_out[i] = lane_a_bigger[i] ? lane_in_a[i] : lane_in_b[i];
                ALU_MIN:  lane_alu_out[i] = lane_a_bigger[i] ? lane_in_b[i] : lane_in_a[i];
                ALU_EXP:  lane_alu_out[i] = lane_exp_out[i];
                ALU_SQRT: lane_alu_out[i] = lane_sqrt_out[i];

                default: lane_alu_out[i] = 0;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 0;
            ready <= 1;
            lane_skid_valid <= 0;

            for (int i = 0; i < LANE_SIZE; i++) begin
                lane_out[i] <= 0;
                lane_out_skid[i] <= 0;
            end
        end else begin
            if (out_valid && out_ready) begin
                if (lane_skid_valid) begin
                    lane_skid_valid <= 0;
                    ready <= 1;

                    for (int i = 0; i < LANE_SIZE; i++) begin
                        lane_out[i] <= lane_out_skid[i];
                    end
                end else begin
                    out_valid <= 0;
                end
            end

            if (valid && ready) begin
                for (int i = 0; i < LANE_SIZE; i++) begin
                    if (!out_valid || (out_valid && out_ready)) begin
                        out_valid   <= 1;
                        lane_out[i] <= lane_alu_out[i];
                    end else begin
                        lane_out_skid[i] <= lane_alu_out[i];
                        lane_skid_valid <= 1;
                        ready <= 0;
                    end
                end
            end
        end
    end

endmodule
