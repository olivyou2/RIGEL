module handshake_distribute_tb;
    localparam ADDR_WIDTH = 16;
    localparam DATA_WIDTH = 32;
    localparam N = 2;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) in_ch();
    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) out_ch[N]();

    handshake_distribute #(.N(N)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(in_ch),
        .out_ch(out_ch)
    );

    int accepted[N];
    for (genvar i = 0; i < N; i++) begin : branch_monitor
        always @(posedge clk) begin
            if (out_ch[i].valid && out_ch[i].ready) begin
                if (out_ch[i].addr !== in_ch.addr || out_ch[i].data !== in_ch.data)
                    $fatal(1, "branch %0d payload mismatch", i);
                accepted[i]++;
            end
        end
    end

    initial begin
        in_ch.valid = 0;
        in_ch.addr = '0;
        in_ch.data = '0;
        out_ch[0].ready = 0;
        out_ch[1].ready = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        // Branch 0 accepts first. It must not see duplicates while branch 1 stalls.
        in_ch.addr = 16'h1234;
        in_ch.data = 32'h89ab_cdef;
        in_ch.valid = 1;
        out_ch[0].ready = 1;
        repeat (3) @(negedge clk);
        if (accepted[0] != 1 || accepted[1] != 0 || in_ch.ready)
            $fatal(1, "independent backpressure failed");
        if (out_ch[0].valid || !out_ch[1].valid)
            $fatal(1, "branch completion mask failed");

        out_ch[1].ready = 1;
        @(negedge clk);
        if (accepted[0] != 1 || accepted[1] != 1)
            $fatal(1, "stalled branch did not receive transaction");

        // With both destinations ready, sustain one complete broadcast per clock.
        for (int seq = 0; seq < 8; seq++) begin
            in_ch.addr = ADDR_WIDTH'(seq);
            in_ch.data = 32'h1000_0000 + seq;
            @(negedge clk);
            if (!in_ch.ready) $fatal(1, "broadcast throughput bubble");
        end
        in_ch.valid = 0;
        @(negedge clk);

        if (accepted[0] != 9 || accepted[1] != 9)
            $fatal(1, "broadcast count mismatch: %0d %0d", accepted[0], accepted[1]);
        $display("PASS handshake_distribute rv_if broadcast");
        $finish;
    end
endmodule
