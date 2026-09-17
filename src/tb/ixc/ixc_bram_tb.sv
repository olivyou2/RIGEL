module ixc_bram_tb;
    localparam WORDS = 256;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic [31:0] read_addr_in[2], ixc_addr_out[2], write_addr_in[2], ixc_write_addr_out[2];
    logic read_addr_valid[2], read_addr_ready[2], read_data_valid[2], read_data_ready[2];
    logic write_data_valid[2], write_data_ready[2];
    logic [127:0] read_data_out[2], write_data_in[2];
    logic [0:0] read_sel[2], write_sel[2];
    logic [31:0] slave_read_addr_out[1], slave_write_addr_out[1];
    logic [127:0] slave_read_data_in[1], slave_write_data_out[1];
    logic slave_read_addr_valid[1], slave_read_addr_ready[1];
    logic slave_read_data_valid[1], slave_read_data_ready[1];
    logic slave_write_data_valid[1], slave_write_data_ready[1];

    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH(1)
    ) dut_read_req[(2)] ();
    for (genvar ch_idx = 0; ch_idx < (2); ch_idx++) begin : connect_dut_read_req
        assign dut_read_req[ch_idx].addr = read_addr_in[ch_idx];
        assign dut_read_req[ch_idx].valid = read_addr_valid[ch_idx];
        assign read_addr_ready[ch_idx] = dut_read_req[ch_idx].ready;
        assign dut_read_req[ch_idx].data = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((128))
    ) dut_read_rsp[(2)] ();
    for (genvar ch_idx = 0; ch_idx < (2); ch_idx++) begin : connect_dut_read_rsp
        assign read_data_out[ch_idx] = dut_read_rsp[ch_idx].data;
        assign read_data_valid[ch_idx] = dut_read_rsp[ch_idx].valid;
        assign dut_read_rsp[ch_idx].ready = read_data_ready[ch_idx];
    end
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH((128))
    ) dut_write_req[(2)] ();
    for (genvar ch_idx = 0; ch_idx < (2); ch_idx++) begin : connect_dut_write_req
        assign dut_write_req[ch_idx].addr = write_addr_in[ch_idx];
        assign dut_write_req[ch_idx].data = write_data_in[ch_idx];
        assign dut_write_req[ch_idx].valid = write_data_valid[ch_idx];
        assign write_data_ready[ch_idx] = dut_write_req[ch_idx].ready;
    end
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH(1)
    ) dut_slave_read_req[(1)] ();
    for (genvar ch_idx = 0; ch_idx < (1); ch_idx++) begin : connect_dut_slave_read_req
        assign slave_read_addr_out[ch_idx] = dut_slave_read_req[ch_idx].addr;
        assign slave_read_addr_valid[ch_idx] = dut_slave_read_req[ch_idx].valid;
        assign dut_slave_read_req[ch_idx].ready = slave_read_addr_ready[ch_idx];
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((128))
    ) dut_slave_read_rsp[(1)] ();
    for (genvar ch_idx = 0; ch_idx < (1); ch_idx++) begin : connect_dut_slave_read_rsp
        assign dut_slave_read_rsp[ch_idx].data = slave_read_data_in[ch_idx];
        assign dut_slave_read_rsp[ch_idx].valid = slave_read_data_valid[ch_idx];
        assign slave_read_data_ready[ch_idx] = dut_slave_read_rsp[ch_idx].ready;
        assign dut_slave_read_rsp[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH((128))
    ) dut_slave_write_req[(1)] ();
    for (genvar ch_idx = 0; ch_idx < (1); ch_idx++) begin : connect_dut_slave_write_req
        assign slave_write_addr_out[ch_idx] = dut_slave_write_req[ch_idx].addr;
        assign slave_write_data_out[ch_idx] = dut_slave_write_req[ch_idx].data;
        assign slave_write_data_valid[ch_idx] = dut_slave_write_req[ch_idx].valid;
        assign dut_slave_write_req[ch_idx].ready = slave_write_data_ready[ch_idx];
    end
    ixc #(
        .DATA_WIDTH(128),
        .MASTER_N(2),
        .SLAVE_N(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ixc_addr_out(ixc_addr_out),
        .ixc_slave_sel(read_sel),
        .ixc_write_addr_out(ixc_write_addr_out),
        .ixc_write_slave_sel(write_sel),
        .read_req(dut_read_req),
        .read_rsp(dut_read_rsp),
        .write_req(dut_write_req),
        .slave_read_req(dut_slave_read_req),
        .slave_read_rsp(dut_slave_read_rsp),
        .slave_write_req(dut_slave_write_req)
    );
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH(1)
    ) memory_read_req ();
    assign memory_read_req.addr = slave_read_addr_out[0];
    assign memory_read_req.valid = slave_read_addr_valid[0];
    assign slave_read_addr_ready[0] = memory_read_req.ready;
    assign memory_read_req.data = '0;
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((128))
    ) memory_read_rsp ();
    assign slave_read_data_in[0] = memory_read_rsp.data;
    assign slave_read_data_valid[0] = memory_read_rsp.valid;
    assign memory_read_rsp.ready = slave_read_data_ready[0];
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH((128))
    ) memory_write_req ();
    assign memory_write_req.addr = slave_write_addr_out[0];
    assign memory_write_req.data = slave_write_data_out[0];
    assign memory_write_req.valid = slave_write_data_valid[0];
    assign slave_write_data_ready[0] = memory_write_req.ready;
    bram_stream #(
        .DATA_WIDTH(128),
        .DATA_DEPTH(WORDS)
    ) memory (
        .clk(clk),
        .rst_n(rst_n),
        .read_req(memory_read_req),
        .read_rsp(memory_read_rsp),
        .write_req(memory_write_req)
    );

    function automatic logic [127:0] pattern(input int index);
        return {
            32'hdeadbeef ^ 32'(index),
            32'h12345678 + 32'(index),
            32'h87654321 - 32'(index),
            32'hcafebabe ^ 32'(index)
        };
    endfunction

    int sent[2], received[2];
    logic [127:0] held[2];
    bit stalled[2];
    int consecutive;

    initial begin
        for (int m = 0; m < 2; m++) begin
            read_sel[m] = 0;
            write_sel[m] = 0;
            read_addr_in[m] = 0;
            read_addr_valid[m] = 0;
            read_data_ready[m] = 0;
            write_addr_in[m] = 0;
            write_data_in[m] = 0;
            write_data_valid[m] = 0;
        end
        repeat (3) @(negedge clk);
        rst_n = 1;

        // Populate the actual synchronous BRAM through IXC.
        begin
            int written, accepted;
            written  = 0;
            accepted = 0;
            while (accepted < WORDS) begin
                write_data_valid[0] = (written < WORDS);
                write_addr_in[0] = 32'(written * 16);
                write_data_in[0] = pattern(written);
                @(posedge clk);
                if (write_data_valid[0] && write_data_ready[0]) written++;
                if (slave_write_data_valid[0] && slave_write_data_ready[0]) accepted++;
                @(negedge clk);
            end
            write_data_valid[0] = 0;
        end
        repeat (4) @(negedge clk);

        for (int cycle = 0; cycle < 1000; cycle++) begin
            read_addr_valid[0] = (sent[0] < WORDS);
            read_addr_in[0] = 32'(sent[0] * 16);
            read_data_ready[0] = !(cycle >= 80 && cycle < 200);
            read_addr_valid[1] = (cycle >= 100 && sent[1] < 64);
            read_addr_in[1] = 32'(sent[1] * 16);
            read_data_ready[1] = 1;
            @(posedge clk);
            // Measure throughput after initial latency, before backpressure.
            if (cycle >= 10 && cycle < 70) begin
                if (!read_addr_ready[0] || !slave_read_addr_valid[0] ||
                    !slave_read_addr_ready[0] || !read_data_valid[0])
                    $fatal(1, "BRAM read pipeline bubble at cycle %0d", cycle);
                consecutive++;
            end
            for (int m = 0; m < 2; m++) begin
                if (stalled[m] && (!read_data_valid[m] || read_data_out[m] !== held[m]))
                    $fatal(1, "BRAM response changed under backpressure");
                stalled[m] = read_data_valid[m] && !read_data_ready[m];
                held[m] = read_data_out[m];
                if (read_addr_valid[m] && read_addr_ready[m]) sent[m]++;
                if (read_data_valid[m] && read_data_ready[m]) begin
                    if (received[m] >= sent[m] || read_data_out[m] !== pattern(received[m]))
                        $fatal(1, "BRAM data/order mismatch master=%0d index=%0d", m, received[m]);
                    received[m]++;
                end
            end
            if (cycle == 190) begin
                if (read_addr_ready[0]) $fatal(1, "stalled master did not backpressure AR");
                if (received[1] != 64)
                    $fatal(1, "stalled master blocked another master's responses");
            end
            @(negedge clk);
        end
        if (received[0] != WORDS || received[1] != 64 || sent[0] != WORDS || sent[1] != 64)
            $fatal(1, "BRAM reads failed to drain");
        $display("PASS BRAM: %0d consecutive clocks at 1 word/clock; 320 correct 128-bit reads",
                 consecutive);
        $display("PASS BRAM: stalled master backpressures safely while the other master drains");

        // Reset with an unconsumed response, then prove fresh traffic still works.
        read_data_ready[0] = 0;
        read_addr_in[0] = 0;
        read_addr_valid[0] = 1;
        do @(posedge clk); while (!read_addr_ready[0]);
        @(negedge clk);
        read_addr_valid[0] = 0;
        repeat (20) @(negedge clk);
        if (!read_data_valid[0]) $fatal(1, "reset test never buffered a response");
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        read_data_ready[0] = 1;
        repeat (10) begin
            @(negedge clk);
            if (read_data_valid[0] || read_data_valid[1] || slave_read_addr_valid[0])
                $fatal(1, "stale read survived reset");
        end
        read_addr_in[0] = 16;
        read_addr_valid[0] = 1;
        do @(posedge clk); while (!read_addr_ready[0]);
        @(negedge clk);
        read_addr_valid[0] = 0;
        do @(posedge clk); while (!read_data_valid[0]);
        if (read_data_out[0] !== pattern(1)) $fatal(1, "post-reset read mismatch");
        $display("PASS BRAM: reset flush and post-reset read");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "BRAM test timeout");
    end
endmodule
