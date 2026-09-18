module vector_core_ixc_sel_tb;
    localparam ADDR_WIDTH = 32;
    localparam MASTER_N = 2;
    localparam SLAVE_N = 7;
    localparam SEL_WIDTH = $clog2(SLAVE_N + 1);

    logic [ADDR_WIDTH-1:0] addr[MASTER_N];
    logic [SEL_WIDTH-1:0] sel[MASTER_N];

    vector_core_ixc_sel #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MASTER_N(MASTER_N),
        .SLAVE_N(SLAVE_N),
        .SEL_WIDTH(SEL_WIDTH)
    ) dut (
        .addr_in(addr),
        .sel_out(sel)
    );

    task automatic check_master0(input logic [31:0] value, input int expected);
        addr[0] = value;
        #1;
        if (int'(sel[0]) != expected)
            $fatal(1, "addr %08h selected %0d, expected %0d", value, sel[0], expected);
    endtask

    initial begin
        addr = '{default: '0};
        check_master0(32'h0000_0000, 0);
        check_master0(32'h0000_ffff, 0);
        check_master0(32'h0001_0000, 1);
        check_master0(32'h0002_1234, 2);
        check_master0(32'h0003_ffff, 3);
        check_master0(32'h0004_0000, 4);
        check_master0(32'h0005_abcd, 5);
        check_master0(32'h0006_ffff, 6);
        check_master0(32'h0007_0000, SLAVE_N);

        // Only the lower 20 bits belong to the local vector-core address map.
        addr[1] = 32'habc4_5678;
        #1;
        if (int'(sel[1]) != 4) $fatal(1, "upper address bits affected local decode");
        addr[1] = 32'hfff9_0000;
        #1;
        if (int'(sel[1]) != SLAVE_N) $fatal(1, "invalid address was not rejected");

        $display("PASS vector_core_ixc_sel address map");
        $finish;
    end
endmodule
