module bram_dp_stream_tb ();
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 64;
    localparam int TEST_COUNT = 16;

    logic clk;
    logic rst_n;

    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(1)) read_req_a ();
    rv_if #(.ADDR_WIDTH(1), .DATA_WIDTH(DATA_WIDTH)) read_rsp_a ();
    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) write_req_a ();
    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(1)) read_req_b ();
    rv_if #(.ADDR_WIDTH(1), .DATA_WIDTH(DATA_WIDTH)) read_rsp_b ();
    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) write_req_b ();

    bram_dp_stream #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_DEPTH(64)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .read_req_a (read_req_a),
        .read_rsp_a (read_rsp_a),
        .write_req_a(write_req_a),
        .read_req_b (read_req_b),
        .read_rsp_b (read_rsp_b),
        .write_req_b(write_req_b)
    );

    always #1 clk = !clk;

    int received_a;
    int received_b;
    int cycle_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            received_a <= 0;
            received_b <= 0;
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            // Different ready patterns exercise each port's backpressure path.
            read_rsp_a.ready <= ((cycle_count % 3) != 0);
            read_rsp_b.ready <= ((cycle_count % 4) != 1);

            if (read_rsp_a.valid && read_rsp_a.ready) begin
                if (read_rsp_a.data !== (64'ha000_0000 + 64'(received_a))) begin
                    $fatal(1, "port A mismatch: index=%0d data=%h",
                           received_a, read_rsp_a.data);
                end
                received_a <= received_a + 1;
            end

            if (read_rsp_b.valid && read_rsp_b.ready) begin
                if (read_rsp_b.data !== (64'hb000_0000 + 64'(received_b))) begin
                    $fatal(1, "port B mismatch: index=%0d data=%h",
                           received_b, read_rsp_b.data);
                end
                received_b <= received_b + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cycle_count = 0;
        received_a = 0;
        received_b = 0;

        read_req_a.valid = 1'b0;
        read_req_a.addr = '0;
        read_req_a.data = '0;
        read_rsp_a.ready = 1'b0;
        write_req_a.valid = 1'b0;
        write_req_a.addr = '0;
        write_req_a.data = '0;

        read_req_b.valid = 1'b0;
        read_req_b.addr = '0;
        read_req_b.data = '0;
        read_rsp_b.ready = 1'b0;
        write_req_b.valid = 1'b0;
        write_req_b.addr = '0;
        write_req_b.data = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Write two disjoint regions concurrently through ports A and B.
        for (int i = 0; i < TEST_COUNT; i++) begin
            @(negedge clk);
            write_req_a.valid = 1'b1;
            write_req_a.addr = i * 8;
            write_req_a.data = 64'ha000_0000 + 64'(i);
            write_req_b.valid = 1'b1;
            write_req_b.addr = (i + TEST_COUNT) * 8;
            write_req_b.data = 64'hb000_0000 + 64'(i);
            @(posedge clk);
            if (!write_req_a.ready || !write_req_b.ready) begin
                $fatal(1, "write port unexpectedly stalled");
            end
        end
        @(negedge clk);
        write_req_a.valid = 1'b0;
        write_req_b.valid = 1'b0;

        // Allow the registered write controls to reach the BRAM.
        repeat (2) @(posedge clk);

        // Read both regions concurrently. Hold each request until accepted.
        fork
            begin
                for (int i = 0; i < TEST_COUNT; i++) begin
                    @(negedge clk);
                    read_req_a.valid = 1'b1;
                    read_req_a.addr = i * 8;
                    do @(posedge clk); while (!read_req_a.ready);
                end
                @(negedge clk);
                read_req_a.valid = 1'b0;
            end
            begin
                for (int i = 0; i < TEST_COUNT; i++) begin
                    @(negedge clk);
                    read_req_b.valid = 1'b1;
                    read_req_b.addr = (i + TEST_COUNT) * 8;
                    do @(posedge clk); while (!read_req_b.ready);
                end
                @(negedge clk);
                read_req_b.valid = 1'b0;
            end
        join

        fork
            begin
                wait (received_a == TEST_COUNT && received_b == TEST_COUNT);
                $display("[BRAM_DP_STREAM_TB] PASS");
                $finish;
            end
            begin
                repeat (200) @(posedge clk);
                $fatal(1, "timeout: received_a=%0d received_b=%0d",
                       received_a, received_b);
            end
        join_any
    end

endmodule
