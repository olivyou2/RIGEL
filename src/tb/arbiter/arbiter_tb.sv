module arbiter_tb ();

    logic clk;
    logic rst_n;

    always #1 clk = !clk;

    localparam DATA_WIDTH = 64;
    localparam N = 4;

    logic [DATA_WIDTH-1:0] data_in[N];
    logic data_valid[N];
    logic data_ready[N];

    logic [DATA_WIDTH-1:0] data_out;
    logic data_out_valid;
    logic data_out_ready;

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) arbiter_in_ch[(N)] ();
    for (genvar ch_idx = 0; ch_idx < (N); ch_idx++) begin : connect_arbiter_in_ch
        assign arbiter_in_ch[ch_idx].data = data_in[ch_idx];
        assign arbiter_in_ch[ch_idx].valid = data_valid[ch_idx];
        assign data_ready[ch_idx] = arbiter_in_ch[ch_idx].ready;
        assign arbiter_in_ch[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH))
    ) arbiter_out_ch ();
    assign data_out = arbiter_out_ch.data;
    assign data_out_valid = arbiter_out_ch.valid;
    assign arbiter_out_ch.ready = data_out_ready;
    arbiter_skid #(
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .N         (N  /* default 2 */)
    ) arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(arbiter_in_ch),
        .out_ch(arbiter_out_ch)
    );

    genvar i;
    generate
        for (i = 0; i < N; i++) begin
            rv_if #(
                .ADDR_WIDTH(1),
                .DATA_WIDTH(32)
            ) hs_prod_dut_out_ch ();
            assign data_in[i] = hs_prod_dut_out_ch.data;
            assign data_valid[i] = hs_prod_dut_out_ch.valid;
            assign hs_prod_dut_out_ch.ready = data_ready[i];
            hs_prod #(
                .BASE_NUM(i * 100),
                .VALID_COUNTER_START((i * 5) % 13)
            ) hs_prod_dut (
                .clk(clk),
                .out_ch(hs_prod_dut_out_ch)
            );
        end
    endgenerate

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(32)
    ) hs_cons_dut_in_ch ();
    assign hs_cons_dut_in_ch.data = data_out;
    assign hs_cons_dut_in_ch.valid = data_out_valid;
    assign data_out_ready = hs_cons_dut_in_ch.ready;
    assign hs_cons_dut_in_ch.addr = '0;
    hs_cons hs_cons_dut (
        .clk  (clk),
        .in_ch(hs_cons_dut_in_ch)
    );

    initial begin
        clk   = 0;
        // rst_n = 0;
        // #10;
        rst_n = 1;
        #1000;
        $finish;
    end

endmodule
;
