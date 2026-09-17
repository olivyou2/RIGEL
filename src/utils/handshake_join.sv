module handshake_join #(
    parameter DATA_WIDTH = 64,
    parameter N = 4
) (
    input logic clk,
    input logic rst_n,
    rv_if.sink in_ch[N],
    // One atomic transfer containing N words; word i is data[i*DATA_WIDTH +: DATA_WIDTH].
    rv_if.source out_ch
);
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH)
    ) buffered[N] ();
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH * N)
    ) joined ();
    logic [N-1:0] buffered_valid;

    assign joined.addr  = '0;
    assign joined.valid = &buffered_valid;

    for (genvar i = 0; i < N; i++) begin : input_buffers
        assign buffered_valid[i] = buffered[i].valid;
        assign joined.data[i*DATA_WIDTH+:DATA_WIDTH] = buffered[i].data;
        assign buffered[i].ready = joined.valid && joined.ready;

        skid #(
            .DATA_WIDTH(DATA_WIDTH)
        ) input_skid (
            .clk(clk),
            .rst_n(rst_n),
            .in_ch(in_ch[i]),
            .out_ch(buffered[i])
        );
    end

    skid #(
        .DATA_WIDTH(DATA_WIDTH * N)
    ) output_skid (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(joined),
        .out_ch(out_ch)
    );
endmodule
