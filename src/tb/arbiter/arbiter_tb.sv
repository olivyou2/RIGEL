module arbiter_tb();

    logic clk;
    logic rst_n;

    always #1 clk = !clk;

    localparam DATA_WIDTH = 64;
    localparam N = 4;

    logic [DATA_WIDTH-1: 0] data_in[N];
    logic data_valid[N];
    logic data_ready[N];

    logic [DATA_WIDTH-1: 0] data_out;
    logic data_out_valid;
    logic data_out_ready;

    arbiter #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .N         (N /* default 2 */)
     ) arbiter (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .data_valid    (data_valid),
        .data_ready    (data_ready),
        .data_out      (data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready)
    );

    genvar i;
    generate
        for (i=0; i<N; i++) begin
            hs_prod #(.BASE_NUM(i*100), .VALID_COUNTER_START((i*5)%13)) hs_prod_dut (
                .clk  (clk),
                .data (data_in[i]),
                .valid(data_valid[i]),
                .ready(data_ready[i])
            );
        end
    endgenerate

    hs_cons hs_cons_dut (
        .clk  (clk),
        .data (data_out),
        .valid(data_out_valid),
        .ready(data_out_ready)
    );

    initial begin
        clk = 0;
        // rst_n = 0;
        // #10;
        rst_n = 1;
        #1000;
        $finish;
    end

endmodule;