module handshake_addr_join #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int TAG_WIDTH = 4,
    parameter int EPOCH_WIDTH = 4
) (
    input logic clk,
    input logic rst_n,

    // Only data and valid/ready are used from this channel.
    rv_if.sink data_in_ch,

    // Only addr and valid/ready are used from this channel.
    rv_if.sink addr_in_ch,

    // One atomic transfer containing both data and address.
    rv_if.source out_ch
);
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) buffered_data ();

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(1),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) buffered_addr ();

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) joined ();

    skid #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) data_input_skid (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (data_in_ch),
        .out_ch(buffered_data)
    );

    skid #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(1),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) addr_input_skid (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (addr_in_ch),
        .out_ch(buffered_addr)
    );

    assign joined.addr  = buffered_addr.addr;
    assign joined.data  = buffered_data.data;
    assign joined.tag   = buffered_addr.tag;
    assign joined.epoch = buffered_addr.epoch;
    assign joined.valid = buffered_data.valid && buffered_addr.valid;

    // Consume both buffered inputs only when the complete pair is accepted.
    assign buffered_data.ready = joined.valid && joined.ready;
    assign buffered_addr.ready = joined.valid && joined.ready;

    skid #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) output_skid (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (joined),
        .out_ch(out_ch)
    );
endmodule
