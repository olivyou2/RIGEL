`timescale 1ns/1ps
module vector_lut_tb;
    parameter LANE_SIZE=16;
    logic [7:0] data_in[LANE_SIZE];
    logic [7:0] exp_out[LANE_SIZE], sqrt_out[LANE_SIZE];

    vector_exp #(.LANE_SIZE(LANE_SIZE)) exp_dut (
        .data_in(data_in), .data_out(exp_out)
    );
    vector_sqrt #(.LANE_SIZE(LANE_SIZE)) sqrt_dut (
        .data_in(data_in), .data_out(sqrt_out)
    );

    logic clk=0, rst_n=0;
    logic valid=0, ready, out_valid, out_ready=0, lane_sel=0;
    logic [4:0] opcode=0;
    logic [7:0] lane_b[LANE_SIZE], lane_out[LANE_SIZE];
    int expected_lane[LANE_SIZE];
    always #5 clk=~clk;
    for (genvar lane=0; lane<LANE_SIZE; lane++) begin: operand_b
        assign lane_b[lane] = ~data_in[lane];
    end
    vector_alu #(.LANE_SIZE(LANE_SIZE)) core_dut (
        .clk(clk), .rst_n(rst_n), .lane_in_a(data_in), .lane_in_b(lane_b),
        .lane_sel(lane_sel), .opcode(opcode), .valid(valid), .ready(ready),
        .lane_out(lane_out), .out_valid(out_valid), .out_ready(out_ready)
    );

    initial begin
        // Every lane visits all 256 bit patterns, with different inputs per lane.
        for (int pattern=0; pattern<256; pattern++) begin
            for (int lane=0; lane<LANE_SIZE; lane++)
                data_in[lane] = 8'(pattern + 17*lane);
            #1;
            for (int lane=0; lane<LANE_SIZE; lane++) begin
                int x, expected_exp, y;
                real exact_exp;
                x = int'($signed(data_in[lane]));
                exact_exp = $exp(real'(x));
                expected_exp = (exact_exp > 127.0) ? 127 : $rtoi(exact_exp);
                if (int'(exp_out[lane]) != expected_exp)
                    $fatal(1, "exp lane=%0d x=%0d got=%0d expected=%0d",
                        lane, x, exp_out[lane], expected_exp);
                y = int'(sqrt_out[lane]);
                // Independent integer-square bounds verify floor(sqrt(x)).
                if (x < 0) begin
                    if (y != 0) $fatal(1, "sqrt negative input x=%0d got=%0d", x, y);
                end else if (y < 0 || y*y > x || (y+1)*(y+1) <= x) begin
                    $fatal(1, "sqrt lane=%0d x=%0d got=%0d", lane, x, y);
                end
            end
        end
        $display("PASS signed int8 exp/sqrt: all 256 inputs on each of %0d lanes", LANE_SIZE);
        // Check opcode/operand selection and response stability under stall.
        @(negedge clk);
        rst_n=1;
        for (int transaction=0; transaction<256; transaction++) begin
            @(negedge clk);
            opcode = (transaction%2 == 0) ? 5'd10 : 5'd11;
            lane_sel = 1'(transaction/2);
            for (int lane=0; lane<LANE_SIZE; lane++) begin
                int x, root;
                real exact_exp;
                data_in[lane] = 8'(transaction + 17*lane);
                x = lane_sel ? int'($signed(~data_in[lane])) : int'($signed(data_in[lane]));
                if (opcode == 10) begin
                    exact_exp = $exp(real'(x));
                    expected_lane[lane] = (exact_exp > 127.0) ? 127 : $rtoi(exact_exp);
                end else begin
                    root=0;
                    while ((root+1)*(root+1) <= x) root++;
                    expected_lane[lane]=root;
                end
            end
            valid=1;
            do @(posedge clk); while (!ready);
            @(negedge clk);
            valid=0;
            repeat (3) begin
                if (!out_valid) $fatal(1, "core dropped valid under stall");
                for (int lane=0; lane<LANE_SIZE; lane++)
                    if (int'(lane_out[lane]) != expected_lane[lane])
                        $fatal(1, "core result mismatch transaction=%0d lane=%0d", transaction, lane);
                @(negedge clk);
            end
            out_ready=1;
            @(negedge clk);
            out_ready=0;
        end
        $display("PASS ALU exp/sqrt selection and stalled responses: %0d lanes", LANE_SIZE);
        $finish;
    end
    initial begin #100000; $fatal(1, "test timeout"); end
endmodule
