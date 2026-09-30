module handshake_join #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter TAG_WIDTH = 4,
    parameter EPOCH_WIDTH = 4,
    parameter N = 4,
    parameter ADDR_SEL = 0  // Input channel whose address is forwarded to out_ch.
) (
    input logic clk,
    input logic rst_n,
    rv_if.sink in_ch[N],
    // One atomic transfer containing N words; word i is data[i*DATA_WIDTH +: DATA_WIDTH].
    rv_if.source out_ch
);
    localparam int OUTPUT_DATA_WIDTH = DATA_WIDTH * N;

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) buffered[N] ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(OUTPUT_DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) joined ();
    logic [N-1:0] buffered_valid;

    assign joined.addr  = buffered[ADDR_SEL].addr;
    assign joined.tag   = buffered[ADDR_SEL].tag;
    assign joined.epoch = buffered[ADDR_SEL].epoch;
    assign joined.valid = &buffered_valid;

    for (genvar i = 0; i < N; i++) begin : input_buffers
        assign buffered_valid[i] = buffered[i].valid;
        assign joined.data[i*DATA_WIDTH+:DATA_WIDTH] = buffered[i].data;
        assign buffered[i].ready = joined.valid && joined.ready;

        skid #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .TAG_WIDTH(TAG_WIDTH),
            .EPOCH_WIDTH(EPOCH_WIDTH)
        ) input_skid (
            .clk(clk),
            .rst_n(rst_n),
            .in_ch(in_ch[i]),
            .out_ch(buffered[i])
        );
    end

    skid #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(OUTPUT_DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) output_skid (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(joined),
        .out_ch(out_ch)
    );

    initial begin
        if (ADDR_SEL < 0 || ADDR_SEL >= N) begin
            $fatal(1, "handshake_join ADDR_SEL (%0d) must be in [0, %0d]",
                   ADDR_SEL, N-1);
        end
    end
endmodule
