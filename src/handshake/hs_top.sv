module hs_top ();
    logic clk = 0;
    always #1 clk = !clk;

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(32)
    ) prod_out_ch ();

    hs_prod prod (
        .clk(clk),
        .out_ch(prod_out_ch)
    );

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(32)
    ) bridge_out_ch ();

    hs_bridge bridge (
        .clk(clk),
        .in_ch(prod_out_ch),
        .out_ch(bridge_out_ch)
    );

    hs_cons cons (
        .clk  (clk),
        .in_ch(bridge_out_ch)
    );

    initial begin
        $display("Handshake testbench started");
        #1000;
        $finish;
    end

endmodule
