module handshake_join_tb ();

    logic clk = 0;
    logic rst_n = 0;

    always #1 clk = !clk;

    localparam DATA_WIDTH = 64;
    localparam ADDR_WIDTH = 16;

    logic [DATA_WIDTH-1:0] data_in[2];
    logic [ADDR_WIDTH-1:0] addr_in[2];
    logic [3:0] tag_in[2];
    logic [3:0] epoch_in[2];
    logic data_in_valid[2];
    logic data_in_ready[2];

    logic [DATA_WIDTH-1:0] data_out[2];
    logic [ADDR_WIDTH-1:0] addr_out;
    logic data_out_valid;
    logic data_out_ready;

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH((DATA_WIDTH))
    ) handshake_join_in_ch[(2)] ();
    for (genvar ch_idx = 0; ch_idx < (2); ch_idx++) begin : connect_handshake_join_in_ch
        assign handshake_join_in_ch[ch_idx].data = data_in[ch_idx];
        assign handshake_join_in_ch[ch_idx].valid = data_in_valid[ch_idx];
        assign data_in_ready[ch_idx] = handshake_join_in_ch[ch_idx].ready;
        assign handshake_join_in_ch[ch_idx].addr = addr_in[ch_idx];
        assign handshake_join_in_ch[ch_idx].tag = tag_in[ch_idx];
        assign handshake_join_in_ch[ch_idx].epoch = epoch_in[ch_idx];
    end
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH((DATA_WIDTH) * (2))
    ) handshake_join_out_ch ();
    for (genvar lane = 0; lane < (2); lane++) begin : connect_handshake_join_data_out
        assign data_out[lane] = handshake_join_out_ch.data[lane*(DATA_WIDTH)+:(DATA_WIDTH)];
    end
    assign data_out_valid = handshake_join_out_ch.valid;
    assign addr_out = handshake_join_out_ch.addr;
    assign handshake_join_out_ch.ready = data_out_ready;
    handshake_join #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .N         (2  /* default 4 */),
        .ADDR_SEL  (1)
    ) handshake_join (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(handshake_join_in_ch),
        .out_ch(handshake_join_out_ch)
    );

    int pass_count = 0;

    task automatic clear_inputs();
        for (int i = 0; i < 2; i++) begin
            data_in[i] = '0;
            addr_in[i] = '0;
            tag_in[i] = '0;
            epoch_in[i] = '0;
            data_in_valid[i] = 1'b0;
        end
        data_out_ready = 1'b0;
    endtask

    task automatic expect_addr(input logic [ADDR_WIDTH-1:0] actual,
                               input logic [ADDR_WIDTH-1:0] expected, input string msg);
        if (actual !== expected) begin
            $fatal(1, "[HANDSHAKE_JOIN_TB] %s (actual=%h expected=%h)", msg, actual, expected);
        end
        pass_count++;
    endtask

    task automatic expect_bit(input logic actual, input logic expected, input string msg);
        if (actual !== expected) begin
            $fatal(1, "[HANDSHAKE_JOIN_TB] %s (actual=%0b expected=%0b)", msg, actual, expected);
        end
        pass_count++;
    endtask

    task automatic expect_word(input logic [DATA_WIDTH-1:0] actual,
                               input logic [DATA_WIDTH-1:0] expected, input string msg);
        if (actual !== expected) begin
            $fatal(1, "[HANDSHAKE_JOIN_TB] %s (actual=%h expected=%h)", msg, actual, expected);
        end
        pass_count++;
    endtask

    task automatic expect_valid_clears_within(input int cycles, input string msg);
        logic cleared;
        cleared = 1'b0;
        for (int i = 0; i < cycles; i++) begin
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
        addr_in[0] = 16'h1001;
        addr_in[1] = 16'h2001;
        tag_in[0] = 4'h1;
        tag_in[1] = 4'h2;
        epoch_in[0] = 4'h3;
        epoch_in[1] = 4'h4;
        data_in_valid[0] = 1'b1;
        data_in_valid[1] = 1'b1;
        data_out_ready = 1'b1;

        @(posedge clk);
        data_in_valid[0] = 1'b0;
        data_in_valid[1] = 1'b0;

        wait (data_out_valid === 1'b1);
        expect_word(data_out[0], 64'h1111_0000_0000_0001, "joined lane0 mismatch (case1)");
        expect_word(data_out[1], 64'h2222_0000_0000_0002, "joined lane1 mismatch (case1)");
        expect_addr(addr_out, 16'h2001, "selected address mismatch (case1)");
        expect_addr({12'b0, handshake_join_out_ch.tag}, 16'h0002, "selected tag mismatch (case1)");
        expect_addr({12'b0, handshake_join_out_ch.epoch}, 16'h0004, "selected epoch mismatch (case1)");

        expect_valid_clears_within(3, "output did not deassert after handshake (case1)");

        // Case 2: output backpressure should hold valid/data stable.
        data_in[0] = 64'hAAAA_0000_0000_0003;
        data_in[1] = 64'hBBBB_0000_0000_0004;
        addr_in[0] = 16'h1002;
        addr_in[1] = 16'h2002;
        data_in_valid[0] = 1'b1;
        data_in_valid[1] = 1'b1;
        data_out_ready = 1'b0;

        @(posedge clk);
        data_in_valid[0] = 1'b0;
        data_in_valid[1] = 1'b0;

        wait (data_out_valid === 1'b1);
        expect_word(data_out[0], 64'hAAAA_0000_0000_0003, "joined lane0 mismatch (case2 hold)");
        expect_word(data_out[1], 64'hBBBB_0000_0000_0004, "joined lane1 mismatch (case2 hold)");
        expect_addr(addr_out, 16'h2002, "selected address mismatch (case2 hold)");

        repeat (3) begin
            @(posedge clk);
            expect_bit(data_out_valid, 1'b1, "output valid dropped under backpressure");
            expect_word(data_out[0], 64'hAAAA_0000_0000_0003, "lane0 changed under backpressure");
            expect_word(data_out[1], 64'hBBBB_0000_0000_0004, "lane1 changed under backpressure");
            expect_addr(addr_out, 16'h2002, "address changed under backpressure");
        end

        data_out_ready = 1'b1;
        expect_valid_clears_within(3, "output did not clear once sink accepted (case2)");

        // Case 3: staggered arrivals should join only after all lanes are present.
        data_out_ready = 1'b1;
        data_in[0] = 64'hCAFE_0000_0000_0005;
        addr_in[0] = 16'h1003;
        data_in_valid[0] = 1'b1;
        @(posedge clk);
        data_in_valid[0] = 1'b0;

        repeat (2) begin
            @(posedge clk);
            expect_bit(data_out_valid, 1'b0, "output asserted before all lanes available");
        end

        data_in[1] = 64'hD00D_0000_0000_0006;
        addr_in[1] = 16'h2003;
        data_in_valid[1] = 1'b1;
        @(posedge clk);
        data_in_valid[1] = 1'b0;

        wait (data_out_valid === 1'b1);
        expect_word(data_out[0], 64'hCAFE_0000_0000_0005, "joined lane0 mismatch (case3)");
        expect_word(data_out[1], 64'hD00D_0000_0000_0006, "joined lane1 mismatch (case3)");
        expect_addr(addr_out, 16'h2003, "selected address mismatch (case3)");

        expect_valid_clears_within(3, "output did not clear after final case");

        $display("[HANDSHAKE_JOIN_TB] PASS (%0d checks)", pass_count);
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "[HANDSHAKE_JOIN_TB] timeout");
    end

endmodule
