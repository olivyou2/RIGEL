module handshake_join_tb();

    logic clk = 0;
    logic rst_n = 0;

    always #1 clk = !clk;
    
    localparam DATA_WIDTH = 64;
    
    logic [DATA_WIDTH-1: 0] data_in[2];
    logic data_in_valid[2];
    logic data_in_ready[2];

    logic [DATA_WIDTH-1: 0] data_out[2];
    logic data_out_valid;
    logic data_out_ready;

    handshake_join #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .N         (2 /* default 4 */)
     ) handshake_join (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .data_in_valid (data_in_valid),
        .data_in_ready (data_in_ready),
        .data_out      (data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready)
    );

    int pass_count = 0;

    task automatic clear_inputs();
        for (int i=0; i<2; i++) begin
            data_in[i] = '0;
            data_in_valid[i] = 1'b0;
        end
        data_out_ready = 1'b0;
    endtask

    task automatic expect_bit(
        input logic actual,
        input logic expected,
        input string msg
    );
        if (actual !== expected) begin
            $fatal(1, "[HANDSHAKE_JOIN_TB] %s (actual=%0b expected=%0b)", msg, actual, expected);
        end
        pass_count++;
    endtask

    task automatic expect_word(
        input logic [DATA_WIDTH-1:0] actual,
        input logic [DATA_WIDTH-1:0] expected,
        input string msg
    );
        if (actual !== expected) begin
            $fatal(1, "[HANDSHAKE_JOIN_TB] %s (actual=%h expected=%h)", msg, actual, expected);
        end
        pass_count++;
    endtask

    task automatic expect_valid_clears_within(
        input int cycles,
        input string msg
    );
        logic cleared;
        cleared = 1'b0;
        for (int i=0; i<cycles; i++) begin
            @(posedge clk);
            if (data_out_valid === 1'b0) begin
                cleared = 1'b1;
                break;
            end
        end

        if (!cleared) begin
            $fatal(1, "[HANDSHAKE_JOIN_TB] %s", msg);
        end
        pass_count++;
    endtask

    initial begin
        clear_inputs();

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Case 1: both inputs valid in same cycle -> one joined output packet.
        data_in[0] = 64'h1111_0000_0000_0001;
        data_in[1] = 64'h2222_0000_0000_0002;
        data_in_valid[0] = 1'b1;
        data_in_valid[1] = 1'b1;
        data_out_ready = 1'b1;

        @(posedge clk);
        data_in_valid[0] = 1'b0;
        data_in_valid[1] = 1'b0;

        wait (data_out_valid === 1'b1);
        expect_word(data_out[0], 64'h1111_0000_0000_0001, "joined lane0 mismatch (case1)");
        expect_word(data_out[1], 64'h2222_0000_0000_0002, "joined lane1 mismatch (case1)");

        expect_valid_clears_within(3, "output did not deassert after handshake (case1)");

        // Case 2: output backpressure should hold valid/data stable.
        data_in[0] = 64'hAAAA_0000_0000_0003;
        data_in[1] = 64'hBBBB_0000_0000_0004;
        data_in_valid[0] = 1'b1;
        data_in_valid[1] = 1'b1;
        data_out_ready = 1'b0;

        @(posedge clk);
        data_in_valid[0] = 1'b0;
        data_in_valid[1] = 1'b0;

        wait (data_out_valid === 1'b1);
        expect_word(data_out[0], 64'hAAAA_0000_0000_0003, "joined lane0 mismatch (case2 hold)");
        expect_word(data_out[1], 64'hBBBB_0000_0000_0004, "joined lane1 mismatch (case2 hold)");

        repeat (3) begin
            @(posedge clk);
            expect_bit(data_out_valid, 1'b1, "output valid dropped under backpressure");
            expect_word(data_out[0], 64'hAAAA_0000_0000_0003, "lane0 changed under backpressure");
            expect_word(data_out[1], 64'hBBBB_0000_0000_0004, "lane1 changed under backpressure");
        end

        data_out_ready = 1'b1;
        expect_valid_clears_within(3, "output did not clear once sink accepted (case2)");

        // Case 3: staggered arrivals should join only after all lanes are present.
        data_out_ready = 1'b1;
        data_in[0] = 64'hCAFE_0000_0000_0005;
        data_in_valid[0] = 1'b1;
        @(posedge clk);
        data_in_valid[0] = 1'b0;

        repeat (2) begin
            @(posedge clk);
            expect_bit(data_out_valid, 1'b0, "output asserted before all lanes available");
        end

        data_in[1] = 64'hD00D_0000_0000_0006;
        data_in_valid[1] = 1'b1;
        @(posedge clk);
        data_in_valid[1] = 1'b0;

        wait (data_out_valid === 1'b1);
        expect_word(data_out[0], 64'hCAFE_0000_0000_0005, "joined lane0 mismatch (case3)");
        expect_word(data_out[1], 64'hD00D_0000_0000_0006, "joined lane1 mismatch (case3)");

        expect_valid_clears_within(3, "output did not clear after final case");

        $display("[HANDSHAKE_JOIN_TB] PASS (%0d checks)", pass_count);
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "[HANDSHAKE_JOIN_TB] timeout");
    end

endmodule