module vector_accumulate_slot #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH = 32,
    parameter LANE_SIZE  = 16
) (
    input logic clk,
    input logic rst_n,

    // data = {raw_control[15:0], packed signed ALU lanes}; lane 0 is LSB.
    // control[6]=1 accumulates; 0 flushes including this beat.
    // control[9:8] selects wrap, signed saturation, or unsigned saturation.
    rv_if.sink data,

    rv_if.source out_ch
);
    localparam DATA_FIELD_WIDTH = DATA_WIDTH * LANE_SIZE;

    logic signed [ACC_WIDTH-1:0] accumulator[LANE_SIZE];
    logic signed [ACC_WIDTH-1:0] next_sum[LANE_SIZE];
    logic [1:0] sat_mode;
    localparam logic signed [ACC_WIDTH-1:0] S8_MAX = 127;
    localparam logic signed [ACC_WIDTH-1:0] S8_MIN = -128;
    localparam logic signed [ACC_WIDTH-1:0] U8_MAX = 255;

    function automatic logic [7:0] narrow_result(
        input logic signed [ACC_WIDTH-1:0] value,
        input logic [1:0] mode
    );
        case (mode)
            2'b01: begin
                if (value > S8_MAX) return 8'h7f;
                if (value < S8_MIN) return 8'h80;
                return value[7:0];
            end
            2'b10: begin
                if (value < 0) return 8'h00;
                if (value > U8_MAX) return 8'hff;
                return value[7:0];
            end
            default: return value[7:0]; // wrap; 2'b11 reserved
        endcase
    endfunction

    logic acc;
    assign acc = data.data[DATA_FIELD_WIDTH+6];
    assign sat_mode = data.data[DATA_FIELD_WIDTH+8+:2];
    assign data.ready = acc || !out_ch.valid || out_ch.ready;
    for (genvar lane = 0; lane < LANE_SIZE; lane++) begin : sum_lanes
        assign next_sum[lane] = accumulator[lane]
            + $signed(data.data[DATA_WIDTH*lane+:DATA_WIDTH]);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i=0; i<LANE_SIZE; i++) begin
                accumulator[i] <= 0;
            end
            out_ch.valid <= 0;
            out_ch.data <= '0;
            out_ch.addr <= '0;
            out_ch.tag <= '0;
            out_ch.epoch <= '0;

        end else begin
            if (out_ch.valid && out_ch.ready) begin
                out_ch.valid <= 0;
            end

            if (data.ready && data.valid) begin
                if (acc) begin
                    for (int i=0; i<LANE_SIZE; i++) begin
                        accumulator[i] <= next_sum[i];
                    end
                end else begin
                    for (int i=0; i<LANE_SIZE; i++) begin
                        accumulator[i] <= 0;
                        out_ch.data[8*i+:8] <= narrow_result(next_sum[i], sat_mode);
                    end

                    out_ch.addr <= data.addr;
                    out_ch.tag <= data.tag;
                    out_ch.epoch <= data.epoch;
                    out_ch.valid <= 1;
                end
            end
        end
    end

endmodule
