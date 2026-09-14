`timescale 1ns/1ps
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

    ixc #(.DATA_WIDTH(128), .MASTER_N(2), .SLAVE_N(1)) dut (
        .clk(clk), .rst_n(rst_n),
        .read_addr_in(read_addr_in), .read_addr_valid(read_addr_valid), .read_addr_ready(read_addr_ready),
        .ixc_addr_out(ixc_addr_out), .ixc_slave_sel(read_sel),
        .read_data_out(read_data_out), .read_data_valid(read_data_valid), .read_data_ready(read_data_ready),
        .write_addr_in(write_addr_in), .write_data_in(write_data_in),
        .write_data_valid(write_data_valid), .write_data_ready(write_data_ready),
        .ixc_write_addr_out(ixc_write_addr_out), .ixc_write_slave_sel(write_sel),
        .slave_read_addr_out(slave_read_addr_out), .slave_read_addr_valid(slave_read_addr_valid),
        .slave_read_addr_ready(slave_read_addr_ready), .slave_read_data_in(slave_read_data_in),
        .slave_read_data_valid(slave_read_data_valid), .slave_read_data_ready(slave_read_data_ready),
        .slave_write_addr_out(slave_write_addr_out), .slave_write_data_out(slave_write_data_out),
        .slave_write_data_valid(slave_write_data_valid), .slave_write_data_ready(slave_write_data_ready)
    );
    bram_stream #(.DATA_WIDTH(128), .DATA_DEPTH(WORDS)) memory (
        .clk(clk), .rst_n(rst_n),
        .read_addr_in(slave_read_addr_out[0]), .read_addr_in_valid(slave_read_addr_valid[0]),
        .read_addr_in_ready(slave_read_addr_ready[0]), .read_data_out(slave_read_data_in[0]),
        .read_data_out_valid(slave_read_data_valid[0]), .read_data_out_ready(slave_read_data_ready[0]),
        .write_addr_in(slave_write_addr_out[0]), .write_data_in(slave_write_data_out[0]),
        .write_data_valid(slave_write_data_valid[0]), .write_data_ready(slave_write_data_ready[0])
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
            read_addr_in[m]=0; read_addr_valid[m]=0; read_data_ready[m]=0;
            write_addr_in[m]=0; write_data_in[m]=0; write_data_valid[m]=0;
        end
        repeat (3) @(negedge clk);
        rst_n=1;

        // Populate the actual synchronous BRAM through IXC.
        begin
            int written, accepted;
            written=0; accepted=0;
            while (accepted<WORDS) begin
                write_data_valid[0]=(written<WORDS);
                write_addr_in[0]=32'(written*16);
                write_data_in[0]=pattern(written);
                @(posedge clk);
                if (write_data_valid[0] && write_data_ready[0]) written++;
                if (slave_write_data_valid[0] && slave_write_data_ready[0]) accepted++;
                @(negedge clk);
            end
            write_data_valid[0]=0;
        end
        repeat (4) @(negedge clk);

        for (int cycle=0; cycle<1000; cycle++) begin
            read_addr_valid[0]=(sent[0]<WORDS);
            read_addr_in[0]=32'(sent[0]*16);
            read_data_ready[0]=!(cycle>=80 && cycle<200);
            read_addr_valid[1]=(cycle>=100 && sent[1]<64);
            read_addr_in[1]=32'(sent[1]*16);
            read_data_ready[1]=1;
            @(posedge clk);
            // Measure throughput after initial latency, before backpressure.
            if (cycle>=10 && cycle<70) begin
                if (!read_addr_ready[0] || !slave_read_addr_valid[0] ||
                    !slave_read_addr_ready[0] || !read_data_valid[0])
                    $fatal(1,"BRAM read pipeline bubble at cycle %0d",cycle);
                consecutive++;
            end
            for (int m=0; m<2; m++) begin
                if (stalled[m] && (!read_data_valid[m] || read_data_out[m]!==held[m]))
                    $fatal(1,"BRAM response changed under backpressure");
                stalled[m]=read_data_valid[m] && !read_data_ready[m];
                held[m]=read_data_out[m];
                if (read_addr_valid[m] && read_addr_ready[m]) sent[m]++;
                if (read_data_valid[m] && read_data_ready[m]) begin
                    if (received[m]>=sent[m] || read_data_out[m]!==pattern(received[m]))
                        $fatal(1,"BRAM data/order mismatch master=%0d index=%0d",m,received[m]);
                    received[m]++;
                end
            end
            if (cycle==190) begin
                if (read_addr_ready[0]) $fatal(1,"stalled master did not backpressure AR");
                if (received[1]!=64) $fatal(1,"stalled master blocked another master's responses");
            end
            @(negedge clk);
        end
        if (received[0]!=WORDS || received[1]!=64 || sent[0]!=WORDS || sent[1]!=64)
            $fatal(1,"BRAM reads failed to drain");
        $display("PASS BRAM: %0d consecutive clocks at 1 word/clock; 320 correct 128-bit reads",consecutive);
        $display("PASS BRAM: stalled master backpressures safely while the other master drains");

        // Reset with an unconsumed response, then prove fresh traffic still works.
        read_data_ready[0]=0;
        read_addr_in[0]=0;
        read_addr_valid[0]=1;
        do @(posedge clk); while (!read_addr_ready[0]);
        @(negedge clk);
        read_addr_valid[0]=0;
        repeat (20) @(negedge clk);
        if (!read_data_valid[0]) $fatal(1,"reset test never buffered a response");
        rst_n=0;
        repeat (3) @(negedge clk);
        rst_n=1;
        read_data_ready[0]=1;
        repeat (10) begin
            @(negedge clk);
            if (read_data_valid[0] || read_data_valid[1] || slave_read_addr_valid[0])
                $fatal(1,"stale read survived reset");
        end
        read_addr_in[0]=16;
        read_addr_valid[0]=1;
        do @(posedge clk); while (!read_addr_ready[0]);
        @(negedge clk);
        read_addr_valid[0]=0;
        do @(posedge clk); while (!read_data_valid[0]);
        if (read_data_out[0]!==pattern(1)) $fatal(1,"post-reset read mismatch");
        $display("PASS BRAM: reset flush and post-reset read");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1,"BRAM test timeout");
    end
endmodule
