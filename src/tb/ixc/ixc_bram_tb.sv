`timescale 1ns/1ps
module ixc_bram_tb;
    localparam WORDS = 256;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic [31:0] read_req_addr[2], read_decode_addr[2], write_req_addr[2], write_decode_addr[2];
    logic read_req_valid[2], read_req_ready[2], read_rsp_valid[2], read_rsp_ready[2];
    logic write_req_valid[2], write_req_ready[2];
    logic [127:0] read_rsp_data[2], write_req_data[2];
    logic [0:0] read_sel[2], write_sel[2];
    logic [31:0] slave_read_req_addr[1], slave_write_req_addr[1];
    logic [127:0] slave_read_rsp_data[1], slave_write_req_data[1];
    logic slave_read_req_valid[1], slave_read_req_ready[1];
    logic slave_read_rsp_valid[1], slave_read_rsp_ready[1];
    logic slave_write_req_valid[1], slave_write_req_ready[1];

    ixc #(.DATA_WIDTH(128), .MASTER_N(2), .SLAVE_N(1)) dut (
        .clk(clk), .rst_n(rst_n),
        .read_req_addr(read_req_addr), .read_req_valid(read_req_valid), .read_req_ready(read_req_ready),
        .read_decode_addr(read_decode_addr), .read_decode_sel(read_sel),
        .read_rsp_data(read_rsp_data), .read_rsp_valid(read_rsp_valid), .read_rsp_ready(read_rsp_ready),
        .write_req_addr(write_req_addr), .write_req_data(write_req_data),
        .write_req_valid(write_req_valid), .write_req_ready(write_req_ready),
        .write_decode_addr(write_decode_addr), .write_decode_sel(write_sel),
        .slave_read_req_addr(slave_read_req_addr), .slave_read_req_valid(slave_read_req_valid),
        .slave_read_req_ready(slave_read_req_ready), .slave_read_rsp_data(slave_read_rsp_data),
        .slave_read_rsp_valid(slave_read_rsp_valid), .slave_read_rsp_ready(slave_read_rsp_ready),
        .slave_write_req_addr(slave_write_req_addr), .slave_write_req_data(slave_write_req_data),
        .slave_write_req_valid(slave_write_req_valid), .slave_write_req_ready(slave_write_req_ready)
    );
    bram_stream #(.DATA_WIDTH(128), .DATA_DEPTH(WORDS)) memory (
        .clk(clk), .rst_n(rst_n),
        .read_req_addr(slave_read_req_addr[0]), .read_req_valid(slave_read_req_valid[0]),
        .read_req_ready(slave_read_req_ready[0]), .read_rsp_data(slave_read_rsp_data[0]),
        .read_rsp_valid(slave_read_rsp_valid[0]), .read_rsp_ready(slave_read_rsp_ready[0]),
        .write_req_addr(slave_write_req_addr[0]), .write_req_data(slave_write_req_data[0]),
        .write_req_valid(slave_write_req_valid[0]), .write_req_ready(slave_write_req_ready[0])
    );

    function automatic logic [127:0] pattern(input int index);
        return {32'hdeadbeef ^ 32'(index), 32'h12345678 + 32'(index),
                32'h87654321 - 32'(index), 32'hcafebabe ^ 32'(index)};
    endfunction

    int sent[2], received[2];
    logic [127:0] held[2];
    bit stalled[2];
    int consecutive;

    initial begin
        for (int m=0; m<2; m++) begin
            read_sel[m]=0; write_sel[m]=0;
            read_req_addr[m]=0; read_req_valid[m]=0; read_rsp_ready[m]=0;
            write_req_addr[m]=0; write_req_data[m]=0; write_req_valid[m]=0;
        end
        repeat (3) @(negedge clk);
        rst_n=1;

        // Populate the actual synchronous BRAM through IXC.
        begin
            int written, accepted;
            written=0; accepted=0;
            while (accepted<WORDS) begin
                write_req_valid[0]=(written<WORDS);
                write_req_addr[0]=32'(written*16);
                write_req_data[0]=pattern(written);
                @(posedge clk);
                if (write_req_valid[0] && write_req_ready[0]) written++;
                if (slave_write_req_valid[0] && slave_write_req_ready[0]) accepted++;
                @(negedge clk);
            end
            write_req_valid[0]=0;
        end
        repeat (4) @(negedge clk);

        for (int cycle=0; cycle<1000; cycle++) begin
            read_req_valid[0]=(sent[0]<WORDS);
            read_req_addr[0]=32'(sent[0]*16);
            read_rsp_ready[0]=!(cycle>=80 && cycle<200);
            read_req_valid[1]=(cycle>=100 && sent[1]<64);
            read_req_addr[1]=32'(sent[1]*16);
            read_rsp_ready[1]=1;
            @(posedge clk);
            // Measure throughput after initial latency, before backpressure.
            if (cycle>=10 && cycle<70) begin
                if (!read_req_ready[0] || !slave_read_req_valid[0] ||
                    !slave_read_req_ready[0] || !read_rsp_valid[0])
                    $fatal(1,"BRAM read pipeline bubble at cycle %0d",cycle);
                consecutive++;
            end
            for (int m=0; m<2; m++) begin
                if (stalled[m] && (!read_rsp_valid[m] || read_rsp_data[m]!==held[m]))
                    $fatal(1,"BRAM response changed under backpressure");
                stalled[m]=read_rsp_valid[m] && !read_rsp_ready[m];
                held[m]=read_rsp_data[m];
                if (read_req_valid[m] && read_req_ready[m]) sent[m]++;
                if (read_rsp_valid[m] && read_rsp_ready[m]) begin
                    if (received[m]>=sent[m] || read_rsp_data[m]!==pattern(received[m]))
                        $fatal(1,"BRAM data/order mismatch master=%0d index=%0d",m,received[m]);
                    received[m]++;
                end
            end
            if (cycle==190) begin
                if (read_req_ready[0]) $fatal(1,"stalled master did not backpressure AR");
                if (received[1]!=64) $fatal(1,"stalled master blocked another master's responses");
            end
            @(negedge clk);
        end
        if (received[0]!=WORDS || received[1]!=64 || sent[0]!=WORDS || sent[1]!=64)
            $fatal(1,"BRAM reads failed to drain");
        $display("PASS BRAM: %0d consecutive clocks at 1 word/clock; 320 correct 128-bit reads",consecutive);
        $display("PASS BRAM: stalled master backpressures safely while the other master drains");

        // Reset with an unconsumed response, then prove fresh traffic still works.
        read_rsp_ready[0]=0;
        read_req_addr[0]=0;
        read_req_valid[0]=1;
        do @(posedge clk); while (!read_req_ready[0]);
        @(negedge clk);
        read_req_valid[0]=0;
        repeat (20) @(negedge clk);
        if (!read_rsp_valid[0]) $fatal(1,"reset test never buffered a response");
        rst_n=0;
        repeat (3) @(negedge clk);
        rst_n=1;
        read_rsp_ready[0]=1;
        repeat (10) begin
            @(negedge clk);
            if (read_rsp_valid[0] || read_rsp_valid[1] || slave_read_req_valid[0])
                $fatal(1,"stale read survived reset");
        end
        read_req_addr[0]=16;
        read_req_valid[0]=1;
        do @(posedge clk); while (!read_req_ready[0]);
        @(negedge clk);
        read_req_valid[0]=0;
        do @(posedge clk); while (!read_rsp_valid[0]);
        if (read_rsp_data[0]!==pattern(1)) $fatal(1,"post-reset read mismatch");
        $display("PASS BRAM: reset flush and post-reset read");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1,"BRAM test timeout");
    end
endmodule
