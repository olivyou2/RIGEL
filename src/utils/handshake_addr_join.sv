module handshake_addr_join #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64
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
    localparam int PACKED_WIDTH = ADDR_WIDTH + DATA_WIDTH;

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH)
    ) buffered_data ();

    // skid buffers data only, so carry the address in its data field.
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(ADDR_WIDTH)
    ) addr_as_data ();

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(ADDR_WIDTH)
    ) buffered_addr ();

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(PACKED_WIDTH)
    ) joined ();

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(PACKED_WIDTH)
    ) buffered_joined ();

    assign addr_as_data.addr  = '0;
    assign addr_as_data.data  = addr_in_ch.addr;
    assign addr_as_data.valid = addr_in_ch.valid;
    assign addr_in_ch.ready   = addr_as_data.ready;

    skid #(
        .DATA_WIDTH(DATA_WIDTH)
    ) data_input_skid (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (data_in_ch),
        .out_ch(buffered_data)
    );

    skid #(
        .DATA_WIDTH(ADDR_WIDTH)
    ) addr_input_skid (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (addr_as_data),
        .out_ch(buffered_addr)
    );

    assign joined.addr  = '0;
    assign joined.data  = {buffered_addr.data, buffered_data.data};
    assign joined.valid = buffered_data.valid && buffered_addr.valid;

    // Consume both buffered inputs only when the complete pair is accepted.
    assign buffered_data.ready = joined.valid && joined.ready;
    assign buffered_addr.ready = joined.valid && joined.ready;

    skid #(
        .DATA_WIDTH(PACKED_WIDTH)
    ) output_skid (
        .clk   (clk),
        .rst_n (rst_n),
        .in_ch (joined),
        .out_ch(buffered_joined)
    );

    assign out_ch.data          = buffered_joined.data[DATA_WIDTH-1:0];
    assign out_ch.addr          = buffered_joined.data[PACKED_WIDTH-1:DATA_WIDTH];
    assign out_ch.valid         = buffered_joined.valid;
    assign buffered_joined.ready = out_ch.ready;
endmodule
