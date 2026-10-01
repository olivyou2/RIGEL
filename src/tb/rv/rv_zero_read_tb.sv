`timescale 1ns/1ps
module rv_zero_read_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(128)) req();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(128)) rsp();

    rv_zero_read dut(.clk(clk), .rst_n(rst_n), .read_req(req), .read_rsp(rsp));

    initial begin
        req.valid = 0;
        req.addr = 0;
        req.data = 0;
        req.tag = 0;
        req.epoch = 0;
        rsp.ready = 0;
        repeat (3) @(posedge clk);
        @(negedge clk) begin
            rst_n = 1;
            req.valid = 1;
            req.addr = 32'h10;
            req.tag = 4'h1;
            req.epoch = 4'hA;
        end
        #1;
        if (!req.ready) $fatal(1, "first request stalled");
        @(posedge clk);
        @(negedge clk) begin
            req.addr = 32'h20;
            req.tag = 4'h2;
        end
        #1;
        if (!req.ready || !rsp.valid || rsp.addr !== 32'h10)
            $fatal(1, "first response missing");
        @(posedge clk);
        @(negedge clk) req.valid = 0;
        #1;
        if (req.ready || !rsp.valid || rsp.addr !== 32'h10 ||
            rsp.tag !== 4'h1 || rsp.epoch !== 4'hA || rsp.data !== 0)
            $fatal(1, "full FIFO failed to retain first response");
        rsp.ready = 1;
        @(posedge clk);
        @(negedge clk) begin
            if (!rsp.valid || rsp.addr !== 32'h20 || rsp.tag !== 4'h2)
                $fatal(1, "second response missing");
            req.valid = 1;
            req.addr = 32'h30;
            req.tag = 4'h3;
        end
        @(posedge clk);
        @(negedge clk) begin
            req.valid = 0;
            if (!rsp.valid || rsp.addr !== 32'h30 || rsp.tag !== 4'h3)
                $fatal(1, "simultaneous enqueue/dequeue failed");
        end
        @(posedge clk);
        @(negedge clk);
        if (rsp.valid) $fatal(1, "response FIFO failed to empty");
        $display("[RV_ZERO_READ_TB] PASS");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "timeout");
    end
endmodule
