module handshake_addr_join_tb ();
    localparam int ADDR_WIDTH = 16;
    localparam int DATA_WIDTH = 32;

    logic clk = 1'b0;
    logic rst_n = 1'b0;

    always #1 clk = !clk;

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH)
    ) data_in_ch ();

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(1)
    ) addr_in_ch ();

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) out_ch ();

    assign data_in_ch.addr = '0;
    assign addr_in_ch.data = '0;

    handshake_addr_join #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .data_in_ch(data_in_ch),
        .addr_in_ch(addr_in_ch),
        .out_ch    (out_ch)
    );

    task automatic send_data(input logic [DATA_WIDTH-1:0] data);
        data_in_ch.data  = data;
        data_in_ch.valid = 1'b1;
        do @(posedge clk); while (!data_in_ch.ready);
        data_in_ch.valid = 1'b0;
    endtask

    task automatic send_addr(input logic [ADDR_WIDTH-1:0] addr);
        addr_in_ch.addr  = addr;
        addr_in_ch.valid = 1'b1;
        do @(posedge clk); while (!addr_in_ch.ready);
        addr_in_ch.valid = 1'b0;
    endtask

    task automatic expect_output(
        input logic [ADDR_WIDTH-1:0] expected_addr,
        input logic [DATA_WIDTH-1:0] expected_data
    );
        while (!out_ch.valid) @(posedge clk);

        if (out_ch.addr !== expected_addr) begin
            $fatal(1, "[HANDSHAKE_ADDR_JOIN_TB] addr=%h expected=%h",
                   out_ch.addr, expected_addr);
        end
        if (out_ch.data !== expected_data) begin
            $fatal(1, "[HANDSHAKE_ADDR_JOIN_TB] data=%h expected=%h",
                   out_ch.data, expected_data);
        end

        @(posedge clk);
    endtask

    initial begin
        data_in_ch.data  = '0;
        data_in_ch.valid = 1'b0;
        addr_in_ch.addr  = '0;
        addr_in_ch.valid = 1'b0;
        out_ch.ready     = 1'b1;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Simultaneous arrival.
        fork
            send_data(32'h1122_3344);
            send_addr(16'h1234);
        join
        expect_output(16'h1234, 32'h1122_3344);

        // Data arrives before address.
        send_data(32'hAABB_CCDD);
        repeat (3) @(posedge clk);
        if (out_ch.valid) $fatal(1, "output valid before address arrived");
        send_addr(16'h5678);
        expect_output(16'h5678, 32'hAABB_CCDD);

        // Address arrives before data.
        send_addr(16'h9ABC);
        repeat (3) @(posedge clk);
        if (out_ch.valid) $fatal(1, "output valid before data arrived");
        send_data(32'h5566_7788);
        expect_output(16'h9ABC, 32'h5566_7788);

        // Output must remain stable while backpressured.
        out_ch.ready = 1'b0;
        fork
            send_data(32'hDEAD_BEEF);
            send_addr(16'hCAFE);
        join
        while (!out_ch.valid) @(posedge clk);
        repeat (3) begin
            @(posedge clk);
            if (!out_ch.valid || out_ch.addr !== 16'hCAFE ||
                out_ch.data !== 32'hDEAD_BEEF) begin
                $fatal(1, "output changed while backpressured");
            end
        end
        out_ch.ready = 1'b1;
        @(posedge clk);

        $display("[HANDSHAKE_ADDR_JOIN_TB] PASS");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "[HANDSHAKE_ADDR_JOIN_TB] timeout");
    end
endmodule
