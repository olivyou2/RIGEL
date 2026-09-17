module ixc_tb;
    parameter MASTER_N=2, SLAVE_N=2, ZERO_LATENCY=0, READ_FIFO_DEPTH=4, READ_OUTSTANDING=8, TARGET_RUN=8;
    localparam ADDR_WIDTH = 32, DATA_WIDTH = 64;
    localparam SEL_WIDTH = $clog2(SLAVE_N + 1);
    logic clk;
    logic rst_n;
    // Master Side
    logic [ADDR_WIDTH-1:0] read_addr_in[MASTER_N];
    logic read_addr_valid[MASTER_N];
    logic read_addr_ready[MASTER_N];
    logic [ADDR_WIDTH-1:0] ixc_addr_out[MASTER_N];
    logic [SEL_WIDTH-1:0] ixc_slave_sel[MASTER_N];
    logic [DATA_WIDTH-1:0] read_data_out[MASTER_N];
    logic read_data_valid[MASTER_N];
    logic read_data_ready[MASTER_N];
    logic [ADDR_WIDTH-1:0] write_addr_in[MASTER_N];
    logic [DATA_WIDTH-1:0] write_data_in[MASTER_N];
    logic write_data_valid[MASTER_N];
    logic write_data_ready[MASTER_N];
    logic [ADDR_WIDTH-1:0] ixc_write_addr_out[MASTER_N];
    logic [SEL_WIDTH-1:0] ixc_write_slave_sel[MASTER_N];
    // Slave Side
    logic [ADDR_WIDTH-1:0] slave_read_addr_out[SLAVE_N];
    logic slave_read_addr_valid[SLAVE_N];
    logic slave_read_addr_ready[SLAVE_N];
    logic [DATA_WIDTH-1:0] slave_read_data_in[SLAVE_N];
    logic slave_read_data_valid[SLAVE_N];
    logic slave_read_data_ready[SLAVE_N];
    logic [ADDR_WIDTH-1 : 0] slave_write_addr_out[SLAVE_N];
    logic [DATA_WIDTH-1:0] slave_write_data_out[SLAVE_N];
    logic slave_write_data_valid[SLAVE_N];
    logic slave_write_data_ready[SLAVE_N];
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH(1)
    ) dut_read_req[(MASTER_N)] ();
    for (genvar ch_idx = 0; ch_idx < (MASTER_N); ch_idx++) begin : connect_dut_read_req
        assign dut_read_req[ch_idx].addr = read_addr_in[ch_idx];
        assign dut_read_req[ch_idx].valid = read_addr_valid[ch_idx];
        assign read_addr_ready[ch_idx] = dut_read_req[ch_idx].ready;
        assign dut_read_req[ch_idx].data = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((64))
    ) dut_read_rsp[(MASTER_N)] ();
    for (genvar ch_idx = 0; ch_idx < (MASTER_N); ch_idx++) begin : connect_dut_read_rsp
        assign read_data_out[ch_idx] = dut_read_rsp[ch_idx].data;
        assign read_data_valid[ch_idx] = dut_read_rsp[ch_idx].valid;
        assign dut_read_rsp[ch_idx].ready = read_data_ready[ch_idx];
    end
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH((64))
    ) dut_write_req[(MASTER_N)] ();
    for (genvar ch_idx = 0; ch_idx < (MASTER_N); ch_idx++) begin : connect_dut_write_req
        assign dut_write_req[ch_idx].addr = write_addr_in[ch_idx];
        assign dut_write_req[ch_idx].data = write_data_in[ch_idx];
        assign dut_write_req[ch_idx].valid = write_data_valid[ch_idx];
        assign write_data_ready[ch_idx] = dut_write_req[ch_idx].ready;
    end
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH(1)
    ) dut_slave_read_req[(SLAVE_N)] ();
    for (genvar ch_idx = 0; ch_idx < (SLAVE_N); ch_idx++) begin : connect_dut_slave_read_req
        assign slave_read_addr_out[ch_idx] = dut_slave_read_req[ch_idx].addr;
        assign slave_read_addr_valid[ch_idx] = dut_slave_read_req[ch_idx].valid;
        assign dut_slave_read_req[ch_idx].ready = slave_read_addr_ready[ch_idx];
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((64))
    ) dut_slave_read_rsp[(SLAVE_N)] ();
    for (genvar ch_idx = 0; ch_idx < (SLAVE_N); ch_idx++) begin : connect_dut_slave_read_rsp
        assign dut_slave_read_rsp[ch_idx].data = slave_read_data_in[ch_idx];
        assign dut_slave_read_rsp[ch_idx].valid = slave_read_data_valid[ch_idx];
        assign slave_read_data_ready[ch_idx] = dut_slave_read_rsp[ch_idx].ready;
        assign dut_slave_read_rsp[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH((32)),
        .DATA_WIDTH((64))
    ) dut_slave_write_req[(SLAVE_N)] ();
    for (genvar ch_idx = 0; ch_idx < (SLAVE_N); ch_idx++) begin : connect_dut_slave_write_req
        assign slave_write_addr_out[ch_idx] = dut_slave_write_req[ch_idx].addr;
        assign slave_write_data_out[ch_idx] = dut_slave_write_req[ch_idx].data;
        assign slave_write_data_valid[ch_idx] = dut_slave_write_req[ch_idx].valid;
        assign dut_slave_write_req[ch_idx].ready = slave_write_data_ready[ch_idx];
    end
    ixc #(
        .MASTER_N(MASTER_N),
        .SLAVE_N(SLAVE_N),
        .SEL_WIDTH(SEL_WIDTH),
        .READ_FIFO_DEPTH(READ_FIFO_DEPTH),
        .READ_OUTSTANDING(READ_OUTSTANDING)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ixc_addr_out(ixc_addr_out),
        .ixc_slave_sel(ixc_slave_sel),
        .ixc_write_addr_out(ixc_write_addr_out),
        .ixc_write_slave_sel(ixc_write_slave_sel),
        .read_req(dut_read_req),
        .read_rsp(dut_read_rsp),
        .write_req(dut_write_req),
        .slave_read_req(dut_slave_read_req),
        .slave_read_rsp(dut_slave_read_rsp),
        .slave_write_req(dut_slave_write_req)
    );
    initial clk = 0;
    always #5 clk = ~clk;
    int read_seq[MASTER_N], write_seq[MASTER_N], write_seen[MASTER_N];
    int read_seen[MASTER_N];
    logic [63:0] mem_data[SLAVE_N][16];
    int mem_due[SLAVE_N][16];
    int mem_head[SLAVE_N], mem_tail[SLAVE_N], mem_count[SLAVE_N];
    int accepted_reads, returned_reads, accepted_writes, completed_writes;
    int simultaneous;
    logic [31:0] held_ra[SLAVE_N], held_wa[SLAVE_N];
    logic [63:0] held_wd[SLAVE_N], held_rd[MASTER_N];
    bit ra_stall[SLAVE_N], wr_stall[SLAVE_N], rd_stall[MASTER_N];

    function automatic logic [63:0] response(input logic [31:0] addr);
        return 64'hfedcba9800000000 ^ {32'b0, addr};
    endfunction

    function automatic logic [31:0] read_address(input int seq, m);
        return 32'(seq * SLAVE_N * MASTER_N + ((seq / TARGET_RUN) % SLAVE_N) * MASTER_N + m);
    endfunction

    for (genvar m = 0; m < MASTER_N; m++) begin
        assign ixc_slave_sel[m] = (ixc_addr_out[m]=='1) ? SEL_WIDTH'(SLAVE_N) : SEL_WIDTH'((ixc_addr_out[m] / MASTER_N) % SLAVE_N);
        assign ixc_write_slave_sel[m] = (ixc_write_addr_out[m]=='1) ? SEL_WIDTH'(SLAVE_N) : SEL_WIDTH'((ixc_write_addr_out[m] / MASTER_N) % SLAVE_N);
    end

    initial begin
        rst_n = 0;
        for (int m = 0; m < MASTER_N; m++) begin
            read_addr_valid[m]  = 0;
            write_data_valid[m] = 0;
            read_data_ready[m]  = 0;
        end
        for (int s = 0; s < SLAVE_N; s++) begin
            slave_read_addr_ready[s]  = 0;
            slave_read_data_valid[s]  = 0;
            slave_write_data_ready[s] = 0;
        end
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (int cycle = 0; cycle < 4500; cycle++) begin
            // Drivers update away from the active edge and hold stalled payloads.
            for (int m = 0; m < MASTER_N; m++) begin
                read_data_ready[m] = (cycle >= 20) &&
                    ((cycle >= 3500) || ($urandom_range(0, 3) == 0));
                if (!read_addr_valid[m] && cycle < 3500) begin
                    read_addr_valid[m] = 1;
                    read_addr_in[m] = read_address(read_seq[m], m);
                end
                if (!write_data_valid[m] && cycle < 3500) begin
                    write_data_valid[m] = 1;
                    write_addr_in[m] = 32'(write_seq[m] * MASTER_N + m);
                    write_data_in[m] = response(write_addr_in[m]);
                end
            end
            for (int s = 0; s < SLAVE_N; s++) begin
                slave_read_addr_ready[s]=(mem_count[s]<16) && (cycle>=20) && ((cycle>=3500) || ($urandom_range(
                    0, 3) != 0));
                slave_write_data_ready[s] = (cycle >= 3500) || ($urandom_range(0, 2) == 0);
                slave_read_data_valid[s]=ZERO_LATENCY ?
                    (slave_read_addr_valid[s] && slave_read_addr_ready[s]) :
                    (mem_count[s]!=0 && cycle>=mem_due[s][mem_head[s]]);
                slave_read_data_in[s] = ZERO_LATENCY ? response(slave_read_addr_out[s]) :
                    mem_data[s][mem_head[s]];
            end
            @(posedge clk);
            for (int m = 0; m < MASTER_N; m++) begin
                // No response is possible during the initial FIFO fill.
                if (cycle < READ_FIFO_DEPTH && !read_addr_ready[m])
                    $fatal(1, "AR burst stalled before FIFO filled");
                if (cycle == 19 && read_addr_ready[m])
                    $fatal(1, "full AR FIFO failed to backpressure");
                if (rd_stall[m] && (!read_data_valid[m] || read_data_out[m] !== held_rd[m]))
                    $fatal(1, "unstable master response");
                rd_stall[m] = read_data_valid[m] && !read_data_ready[m];
                held_rd[m]  = read_data_out[m];
                if (read_addr_valid[m] && read_addr_ready[m]) begin
                    accepted_reads++;
                    read_seq[m]++;
                end
                if (read_data_valid[m] && read_data_ready[m]) begin
                    if (read_seen[m] >= read_seq[m] || read_data_out[m] !== response(
                            read_address(read_seen[m], m)
                        ))
                        $fatal(1, "read mismatch master %0d", m);
                    read_seen[m]++;
                    returned_reads++;
                end
                if (write_data_valid[m] && write_data_ready[m]) begin
                    accepted_writes++;
                    write_seq[m]++;
                end
            end
            begin
                int active;
                active = 0;
                for (int s = 0; s < SLAVE_N; s++) begin
                    if (ra_stall[s] && (!slave_read_addr_valid[s] || slave_read_addr_out[s]!==held_ra[s]))
                        $fatal(1, "unstable slave read");
                    if (wr_stall[s] && (!slave_write_data_valid[s] || slave_write_addr_out[s]!==held_wa[s] || slave_write_data_out[s]!==held_wd[s]))
                        $fatal(1, "unstable slave write");
                    ra_stall[s] = slave_read_addr_valid[s] && !slave_read_addr_ready[s];
                    wr_stall[s] = slave_write_data_valid[s] && !slave_write_data_ready[s];
                    held_ra[s]  = slave_read_addr_out[s];
                    held_wa[s]  = slave_write_addr_out[s];
                    held_wd[s]  = slave_write_data_out[s];
                    if (!ZERO_LATENCY && slave_read_data_valid[s] && slave_read_data_ready[s]) begin
                        if (mem_count[s] == 0) $fatal(1, "response without request");
                        mem_head[s] = (mem_head[s] + 1) % 16;
                        mem_count[s]--;
                    end
                    if (slave_read_addr_valid[s] && slave_read_addr_ready[s]) begin
                        if ((slave_read_addr_out[s] / MASTER_N) % SLAVE_N != s)
                            $fatal(1, "read slave routing mismatch");
                        if (!ZERO_LATENCY) begin
                            if (mem_count[s] >= 16) $fatal(1, "slave model overrun");
                            mem_data[s][mem_tail[s]] = response(slave_read_addr_out[s]);
                            mem_due[s][mem_tail[s]] = cycle + int'($urandom_range(1, 12));
                            mem_tail[s] = (mem_tail[s] + 1) % 16;
                            mem_count[s]++;
                        end
                    end
                    if (slave_write_data_valid[s] && slave_write_data_ready[s]) begin
                        int m, seq;
                        m   = int'(slave_write_addr_out[s] % MASTER_N);
                        seq = int'(slave_write_addr_out[s] / MASTER_N);
                        if ((slave_write_addr_out[s]/MASTER_N)%SLAVE_N != s || slave_write_data_out[s]!==response(
                                slave_write_addr_out[s]
                            ) || seq != write_seen[m])
                            $fatal(1, "write routing/data/order mismatch");
                        write_seen[m]++;
                        completed_writes++;
                        active++;
                    end
                end
                if (active > 1) simultaneous++;
            end
            // Remember handshakes before DUT state advances.
            begin
                bit rdone[MASTER_N], wdone[MASTER_N];
                for (int m = 0; m < MASTER_N; m++) begin
                    rdone[m] = read_addr_valid[m] && read_addr_ready[m];
                    wdone[m] = write_data_valid[m] && write_data_ready[m];
                end
                @(negedge clk);
                for (int m = 0; m < MASTER_N; m++) begin
                    if (rdone[m]) read_addr_valid[m] = 0;
                    if (wdone[m]) write_data_valid[m] = 0;
                end
            end
        end
        $display("PASS AR FIFO depth=%0d: burst acceptance, full stall, ordered drain",
                 READ_FIFO_DEPTH);
        if (accepted_reads!=returned_reads || accepted_writes!=completed_writes || returned_reads<50 || completed_writes<50)
            $fatal(
                1,
                "lost transactions R %0d/%0d W %0d/%0d",
                returned_reads,
                accepted_reads,
                completed_writes,
                accepted_writes
            );
        if (MASTER_N > 1 && SLAVE_N > 1 && simultaneous == 0) $fatal(1, "no parallel transfers");
        // Invalid decode values must not accept or route requests.
        for (int m = 0; m < MASTER_N; m++) begin
            read_addr_in[m] = '1;
            write_addr_in[m] = '1;
            read_addr_valid[m] = 1;
            write_data_valid[m] = 1;
        end
        repeat (4) begin
            @(posedge clk);
            for (int m = 0; m < MASTER_N; m++)
            if (read_addr_ready[m] || write_data_ready[m]) $fatal(1, "invalid decode accepted");
            @(negedge clk);
        end
        // Flush queued/stalled requests and response ownership synchronously.
        for (int m = 0; m < MASTER_N; m++) begin
            read_addr_in[m]  = 0;
            write_addr_in[m] = 0;
        end
        for (int s = 0; s < SLAVE_N; s++) begin
            slave_read_addr_ready[s]  = 0;
            slave_write_data_ready[s] = 0;
            slave_read_data_valid[s]  = 0;
        end
        repeat (30) @(negedge clk);
        rst_n = 0;
        for (int m = 0; m < MASTER_N; m++) begin
            read_addr_valid[m]  = 0;
            write_data_valid[m] = 0;
        end
        repeat (2) @(negedge clk);
        rst_n = 1;
        repeat (4) begin
            @(negedge clk);
            for (int m = 0; m < MASTER_N; m++)
            if (read_data_valid[m] || !read_addr_ready[m] || !write_data_ready[m])
                $fatal(1, "master state not reset");
            for (int s = 0; s < SLAVE_N; s++)
            if (slave_read_addr_valid[s] || slave_write_data_valid[s] || slave_read_data_ready[s])
                $fatal(1, "slave state not reset");
        end
        // One master must sustain one write per clock without arbitration bubbles.
        // Then fill both queues under stall and verify lossless recovery/drain.
        begin
            int sent, received, consecutive;
            sent = 0;
            received = 0;
            consecutive = 0;
            for (int cycle = 0; cycle < 400; cycle++) begin
                write_data_valid[0] = (sent < 200);
                write_addr_in[0] = 32'(sent * MASTER_N * SLAVE_N);
                write_data_in[0] = response(write_addr_in[0]);
                slave_write_data_ready[0]=!(cycle>=80 && cycle<105) &&
                    ((cycle<160 || cycle>=300) || $urandom_range(0, 1) == 1);
                @(posedge clk);
                if (cycle >= 10 && cycle < 70) begin
                    if (!slave_write_data_valid[0] || !write_data_ready[0])
                        $fatal(1, "write pipeline bubble during steady streaming");
                    consecutive++;
                end
                if (write_data_valid[0] && write_data_ready[0]) sent++;
                if (slave_write_data_valid[0] && slave_write_data_ready[0]) begin
                    if (received>=sent || slave_write_addr_out[0]!==32'(received*MASTER_N*SLAVE_N) ||
                        slave_write_data_out[0]!==response(
                            32'(received * MASTER_N * SLAVE_N)
                        ))
                        $fatal(1, "buffered write lost, duplicated or reordered");
                    received++;
                end
                @(negedge clk);
            end
            if (sent != 200 || received != 200) $fatal(1, "buffered write drain failed");
            $display("PASS write streaming: %0d consecutive clocks, %0d writes with stall/recovery",
                     consecutive, received);
        end
        $display("PASS %0dx%0d reads=%0d writes=%0d parallel=%0d", MASTER_N, SLAVE_N,
                 returned_reads, completed_writes, simultaneous);
        $finish;
    end
    always @(posedge clk) begin
        if (rst_n) begin
            for (int m = 0; m < MASTER_N; m++)
            if (dut.control.write_input_count[m] > 2 || dut.control.write_inflight[m] > 2)
                $fatal(1, "write master queue overflow");
            for (int s = 0; s < SLAVE_N; s++)
            if (dut.control.write_output_count[s] > 2) $fatal(1, "write slave queue overflow");
        end
    end
    for (genvar m = 0; m < MASTER_N; m++) begin : check_read_master
        always @(posedge clk)
            if (rst_n) begin
                if (int'(dut.read_path.master_queue[m].ar_count)>READ_FIFO_DEPTH ||
                int'(dut.read_path.inflight[m])>READ_OUTSTANDING ||
                dut.read_path.master_queue[m].response_count>dut.read_path.inflight[m])
                    $fatal(1, "read master credit/queue overflow");
                begin
                    int pushes;
                    pushes = 0;
                    for (int s = 0; s < SLAVE_N; s++)
                    if (dut.read_path.response_take[s] && int'(dut.read_path.owner[s]) == m)
                        pushes++;
                    if (pushes > 1) $fatal(1, "multiple responses to one master in a cycle");
                end
            end
    end
    for (genvar s = 0; s < SLAVE_N; s++) begin : check_read_slave
        always @(posedge clk)
            if (rst_n) begin
                if (int'(dut.read_path.slave_queue[s].count)>READ_OUTSTANDING ||
                dut.read_path.slave_queue[s].unsent_count>dut.read_path.slave_queue[s].count)
                    $fatal(1, "read slave owner/AR queue overflow");
            end
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
