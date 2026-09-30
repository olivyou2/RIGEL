`timescale 1ns/1ps
module bram_dp_stream_arbitration_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;

    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) read_req_a();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) read_rsp_a();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) write_req_a();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) read_req_b();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) read_rsp_b();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) write_req_b();

    bram_dp_stream #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .DATA_DEPTH(64)) dut (
        .clk(clk), .rst_n(rst_n),
        .read_req_a(read_req_a), .read_rsp_a(read_rsp_a), .write_req_a(write_req_a),
        .read_req_b(read_req_b), .read_rsp_b(read_rsp_b), .write_req_b(write_req_b)
    );

    initial begin
        read_req_a.valid = 0;
        read_req_a.addr = 0;
        read_req_a.data = 0;
        read_req_a.tag = 0;
        read_req_a.epoch = 0;
        read_rsp_a.ready = 0;
        write_req_a.valid = 0;
        write_req_a.addr = 0;
        write_req_a.data = 0;
        write_req_a.tag = 0;
        write_req_a.epoch = 0;
        read_req_b.valid = 0;
        read_req_b.addr = 0;
        read_req_b.data = 0;
        read_req_b.tag = 0;
        read_req_b.epoch = 0;
        read_rsp_b.ready = 1;
        write_req_b.valid = 0;
        write_req_b.addr = 0;
        write_req_b.data = 0;
        write_req_b.tag = 0;
        write_req_b.epoch = 0;

        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1;
        write_req_a.valid = 1;
        write_req_a.addr = 8;
        write_req_a.data = 64'h1111_2222_3333_4444;
        @(posedge clk);
        if (!write_req_a.ready) $fatal(1, "initial write stalled");
        @(negedge clk) write_req_a.valid = 0;
        repeat (2) @(posedge clk);

        // One physical port cannot accept these two different addresses at
        // once. The write wins; the read must wait without losing its payload.
        @(negedge clk);
        read_req_a.valid = 1;
        read_req_a.addr = 8;
        read_req_a.tag = 4'hA;
        read_req_a.epoch = 4'h5;
        write_req_a.valid = 1;
        write_req_a.addr = 16;
        write_req_a.data = 64'h5555_6666_7777_8888;
        @(posedge clk);
        if (!write_req_a.ready || read_req_a.ready)
            $fatal(1, "same-port read/write were both accepted");
        @(negedge clk) write_req_a.valid = 0;
        @(posedge clk);
        if (!read_req_a.ready) $fatal(1, "pending read did not resume");
        @(negedge clk) read_req_a.valid = 0;
        wait (read_rsp_a.valid);
        if (read_rsp_a.data !== 64'h1111_2222_3333_4444 ||
            read_rsp_a.addr !== 32'd8 || read_rsp_a.tag !== 4'hA ||
            read_rsp_a.epoch !== 4'h5)
            $fatal(1, "pending read response mismatch");
        read_rsp_a.ready = 1;
        @(posedge clk);
        @(negedge clk) read_rsp_a.ready = 0;

        read_req_a.valid = 1;
        read_req_a.addr = 16;
        @(posedge clk);
        if (!read_req_a.ready) $fatal(1, "second read stalled");
        @(negedge clk) read_req_a.valid = 0;
        wait (read_rsp_a.valid);
        if (read_rsp_a.data !== 64'h5555_6666_7777_8888)
            $fatal(1, "write was lost while read waited");
        $display("[BRAM_DP_STREAM_ARBITRATION_TB] PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
