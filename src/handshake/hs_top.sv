module hs_top();
    logic clk = 0;
    always #1 clk = !clk;

    logic [31:0] ptb_data;
    logic ptb_valid;
    logic ptb_ready;

    logic [31:0] btc_data;
    logic btc_valid;
    logic btc_ready;

    hs_prod prod(
        .clk(clk),
        .data(ptb_data),
        .valid(ptb_valid),
        .ready(ptb_ready)
    );

    hs_bridge bridge(
        .clk(clk),
        .data_in(ptb_data),
        .data_in_valid(ptb_valid),
        .data_in_ready(ptb_ready),

        .data_out(btc_data),
        .data_out_valid(btc_out_valid),
        .data_out_ready(btc_out_ready)
    );

    hs_cons cons(
        .clk(clk),
        .data(btc_data),
        .valid(btc_out_valid),
        .ready(btc_out_ready)
    );

    initial begin
        $display("Handshake testbench started");
        #1000;
        $finish;
    end

endmodule