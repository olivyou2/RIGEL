`timescale 1ns/1ps
module banked_bram_stream_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;

    localparam int N = 3;
    rv_if #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) read_req[N]();
    rv_if #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) read_rsp[N]();
    rv_if #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) write_req[N]();
    logic [N-1:0] r_valid, r_ready, q_valid, q_ready, w_valid, w_ready;
    logic [7:0] r_addr[N], q_addr[N], w_addr[N];
    logic [31:0] q_data[N], w_data[N];
    logic [3:0] r_tag[N], q_tag[N], r_epoch[N], q_epoch[N];
    bit stream_check = 0;
    int stream_received = 0;
    int stream_cycle = 0;
    int last_response_cycle = -1;
    bit stall_check = 0;
    int stall_accepted = 0;
    int stall_received = 0;

    always @(posedge clk) if (stream_check) begin
        if (q_valid[0] && q_ready[0]) begin
            if (q_data[0] !== 32'h4444)
                $fatal(1, "stream response data mismatch");
            if (last_response_cycle >= 0 && stream_cycle != last_response_cycle + 1)
                $fatal(1, "stream response bubble");
            stream_received++;
            last_response_cycle = stream_cycle;
        end
        stream_cycle++;
    end

    always @(posedge clk) if (stall_check) begin
        if (r_valid[0] && r_ready[0]) stall_accepted++;
        if (q_valid[0] && q_ready[0]) begin
            if (q_data[0] !== 32'h4444 || q_addr[0] !== 8'h04)
                $fatal(1, "backpressure response mismatch");
            stall_received++;
        end
    end

    always @(posedge clk) if (rst_n) begin
        for (int b = 0; b < 4; b++) begin
            if (dut.core.slot_valid[b][0] && dut.core.slot_valid[b][1] &&
                (dut.core.slot_write[b][0] || dut.core.slot_write[b][1]) &&
                dut.core.slot_addr[b][0][5:2] == dut.core.slot_addr[b][1][5:2])
                $fatal(1, "same-word bank collision");
        end
    end

    for (genvar p = 0; p < N; p++) begin : clients
        assign read_req[p].valid = r_valid[p];
        assign read_req[p].addr = r_addr[p];
        assign read_req[p].data = '0;
        assign read_req[p].tag = r_tag[p];
        assign read_req[p].epoch = r_epoch[p];
        assign r_ready[p] = read_req[p].ready;
        assign q_valid[p] = read_rsp[p].valid;
        assign q_addr[p] = read_rsp[p].addr;
        assign q_data[p] = read_rsp[p].data;
        assign q_tag[p] = read_rsp[p].tag;
        assign q_epoch[p] = read_rsp[p].epoch;
        assign read_rsp[p].ready = q_ready[p];
        assign write_req[p].valid = w_valid[p];
        assign write_req[p].addr = w_addr[p];
        assign write_req[p].data = w_data[p];
        assign write_req[p].tag = '0;
        assign write_req[p].epoch = '0;
        assign w_ready[p] = write_req[p].ready;
    end

    banked_bram_stream #(
        .BANKS(4), .READ_PORTS(N), .WRITE_PORTS(N),
        .DATA_WIDTH(32), .WORDS_PER_BANK(16), .ADDR_WIDTH(8)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .read_req(read_req), .read_rsp(read_rsp), .write_req(write_req)
    );

    task automatic check_response(input int p, input logic [7:0] addr,
                                  input logic [31:0] data);
        if (!q_valid[p] || q_addr[p] !== addr || q_data[p] !== data ||
            q_tag[p] !== 4'(p+1) || q_epoch[p] !== 4'hA)
            $fatal(1, "port %0d response mismatch: valid=%b addr=%h data=%h tag=%h epoch=%h",
                   p, q_valid[p], q_addr[p], q_data[p], q_tag[p], q_epoch[p]);
    endtask

    initial begin
        r_valid = '0;
        w_valid = '0;
        q_ready = '0;
        for (int p = 0; p < N; p++) begin
            r_addr[p] = '0;
            r_tag[p] = 4'(p+1);
            r_epoch[p] = 4'hA;
            w_addr[p] = '0;
            w_data[p] = '0;
        end
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1;

        // The top two address bits select independent banks. Same word index
        // in three banks can be written and then read concurrently.
        w_valid = 3'b111;
        w_addr[0] = 8'h00; w_data[0] = 32'h1111;
        w_addr[1] = 8'h40; w_data[1] = 32'h2222;
        w_addr[2] = 8'h80; w_data[2] = 32'h3333;
        #1;
        if (w_ready !== 3'b111) $fatal(1, "different-bank writes stalled");
        @(posedge clk);
        @(negedge clk) w_valid = '0;
        r_valid = 3'b111;
        r_addr[0] = 8'h00;
        r_addr[1] = 8'h40;
        r_addr[2] = 8'h80;
        #1;
        if (r_ready !== 3'b111) $fatal(1, "different-bank reads stalled");
        @(posedge clk);
        @(negedge clk) r_valid = '0;
        wait (&q_valid);
        check_response(0, 8'h00, 32'h1111);
        check_response(1, 8'h40, 32'h2222);
        check_response(2, 8'h80, 32'h3333);
        q_ready = 3'b111;
        @(posedge clk);
        @(negedge clk) q_ready = '0;

        // All three requests enter independent input FIFOs. The bank drains
        // at most two of them per cycle.
        w_valid = 3'b111;
        w_addr[0] = 8'h04; w_data[0] = 32'h4444;
        w_addr[1] = 8'h08; w_data[1] = 32'h5555;
        w_addr[2] = 8'h0c; w_data[2] = 32'h6666;
        #1;
        if (w_ready !== 3'b111) $fatal(1, "write input FIFO stalled");
        @(posedge clk);
        @(negedge clk) w_valid = '0;

        // Two reads of that bank proceed together and responses route to
        // their original logical ports with stable metadata.
        r_valid = 3'b011;
        r_addr[0] = 8'h04;
        r_addr[1] = 8'h08;
        #1;
        if (r_ready[1:0] !== 2'b11) $fatal(1, "read input FIFO stalled");
        @(posedge clk);
        @(negedge clk) r_valid = '0;
        wait (q_valid[0] && q_valid[1]);
        check_response(0, 8'h04, 32'h4444);
        check_response(1, 8'h08, 32'h5555);
        q_ready = 3'b011;
        @(posedge clk);
        @(negedge clk) q_ready = '0;

        // A third read to the same bank queues behind the two physical
        // ports. All three responses must remain stable under backpressure.
        r_valid = 3'b111;
        r_addr[0] = 8'h04;
        r_addr[1] = 8'h08;
        r_addr[2] = 8'h0c;
        #1;
        if (r_ready !== 3'b111) $fatal(1, "read input FIFO stalled");
        @(posedge clk);
        @(negedge clk) r_valid = '0;
        wait (&q_valid);
        repeat (3) @(posedge clk);
        check_response(0, 8'h04, 32'h4444);
        check_response(1, 8'h08, 32'h5555);
        check_response(2, 8'h0c, 32'h6666);
        @(negedge clk) q_ready = 3'b111;
        @(posedge clk);
        @(negedge clk) q_ready = '0;

        // One read and one write to different words also run in parallel.
        r_valid[0] = 1;
        r_addr[0] = 8'h0c;
        w_valid[0] = 1;
        w_addr[0] = 8'h10;
        w_data[0] = 32'h7777;
        #1;
        if (!r_ready[0] || !w_ready[0]) $fatal(1, "1R+1W stalled");
        @(posedge clk);
        @(negedge clk) begin r_valid = '0; w_valid = '0; end
        wait (q_valid[0]);
        check_response(0, 8'h0c, 32'h6666);
        q_ready[0] = 1;
        @(posedge clk);
        @(negedge clk) q_ready = '0;

        // A continuously ready client can issue and receive one read per
        // clock after the synchronous BRAM/FIFO pipeline fills.
        stream_received = 0;
        stream_cycle = 0;
        last_response_cycle = -1;
        stream_check = 1;
        q_ready[0] = 1;
        r_valid[0] = 1;
        r_addr[0] = 8'h04;
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            if (!r_ready[0]) $fatal(1, "stream request bubble at beat %0d", i);
        end
        @(negedge clk) r_valid = '0;
        wait (stream_received == 8);
        @(negedge clk) begin
            stream_check = 0;
            q_ready = '0;
        end

        // A stalled response fills the reservations and then the two-entry
        // input queue. Releasing backpressure must return every accepted beat.
        stall_accepted = 0;
        stall_received = 0;
        stall_check = 1;
        r_valid[0] = 1;
        r_addr[0] = 8'h04;
        repeat (12) @(posedge clk);
        @(negedge clk);
        if (r_ready[0]) $fatal(1, "read input FIFO failed to backpressure");
        if (stall_accepted != 6) $fatal(1, "unexpected reservation count %0d", stall_accepted);
        r_valid[0] = 0;
        q_ready[0] = 1;
        wait (stall_received == stall_accepted);
        @(negedge clk) begin
            stall_check = 0;
            q_ready = '0;
        end

        // Same-word writes both enter input FIFOs; arbitration must serialize
        // them before they reach the two physical ports.
        w_valid = 3'b011;
        w_addr[0] = 8'h14;
        w_addr[1] = 8'h14;
        #1;
        if (w_ready[1:0] !== 2'b11) $fatal(1, "same-word writes not queued");
        @(posedge clk);
        @(negedge clk) w_valid = '0;
        repeat (3) @(posedge clk);
        $display("[BANKED_BRAM_STREAM_TB] PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
