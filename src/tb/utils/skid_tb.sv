module skid_tb ();
    localparam int ADDR_WIDTH = 16;
    localparam int DATA_WIDTH = 32;

    logic clk = 1'b0;
    logic rst_n = 1'b0;

    always #1 clk = !clk;

    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) in_ch ();
    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) out_ch ();

    skid #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (in_ch),
        .out_ch(out_ch)
    );

    task automatic expect_packet(
        input logic [ADDR_WIDTH-1:0] expected_addr,
        input logic [DATA_WIDTH-1:0] expected_data,
        input logic [3:0] expected_tag,
        input logic [3:0] expected_epoch
    );
        if (!out_ch.valid || out_ch.addr !== expected_addr ||
            out_ch.data !== expected_data || out_ch.tag !== expected_tag ||
            out_ch.epoch !== expected_epoch) begin
            $fatal(1,
                   "[SKID_TB] packet mismatch: valid=%0b addr=%h data=%h tag=%h epoch=%h",
                   out_ch.valid, out_ch.addr, out_ch.data, out_ch.tag, out_ch.epoch);
        end
    endtask

    initial begin
        in_ch.valid = 1'b0;
        in_ch.addr  = '0;
        in_ch.data  = '0;
        in_ch.tag   = '0;
        in_ch.epoch = '0;
        out_ch.ready = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // First packet occupies the output register while the sink is stalled.
        @(negedge clk);
        in_ch.valid = 1'b1;
        in_ch.addr  = 16'h1234;
        in_ch.data  = 32'hAAAA_0001;
        in_ch.tag   = 4'h3;
        in_ch.epoch = 4'h7;
        @(posedge clk);

        // The second packet must enter the skid register with its address.
        @(negedge clk);
        in_ch.addr = 16'h5678;
        in_ch.data = 32'hBBBB_0002;
        in_ch.tag = 4'hA;
        in_ch.epoch = 4'hC;
        @(posedge clk);
        @(negedge clk);
        in_ch.valid = 1'b0;

        expect_packet(16'h1234, 32'hAAAA_0001, 4'h3, 4'h7);
        repeat (2) begin
            @(posedge clk);
            expect_packet(16'h1234, 32'hAAAA_0001, 4'h3, 4'h7);
        end

        // Consuming the first packet promotes the buffered packet atomically.
        @(negedge clk);
        out_ch.ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        expect_packet(16'h5678, 32'hBBBB_0002, 4'hA, 4'hC);

        @(posedge clk);
        @(negedge clk);
        if (out_ch.valid) begin
            $fatal(1, "[SKID_TB] output valid did not clear");
        end

        $display("[SKID_TB] PASS");
        $finish;
    end

    initial begin
        #200;
        $fatal(1, "[SKID_TB] timeout");
    end
endmodule
