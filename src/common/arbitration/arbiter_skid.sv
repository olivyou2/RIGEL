// N-to-1 request arbiter with registered address/data and a matching selection tag.
module arbiter_skid #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 32,
    parameter TAG_WIDTH = 4,
    parameter EPOCH_WIDTH = 4,
    parameter N = 2
) (
    input logic clk,
    input logic rst_n,
    rv_if.sink in_ch[N],
    rv_if.source out_ch,
    output logic [$clog2(N)-1:0] data_out_sel
);
    localparam N_WIDTH = $clog2(N);
    logic [N_WIDTH-1:0] selected;
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) arbitrated ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH + N_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) tagged_in ();
    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH + N_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) tagged_out ();

    arbiter #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH),
        .N(N)
    ) arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(in_ch),
        .out_ch(arbitrated),
        .data_out_sel(selected)
    );

    assign tagged_in.addr   = arbitrated.addr;
    assign tagged_in.data   = {arbitrated.data, selected};
    assign tagged_in.valid  = arbitrated.valid;
    assign tagged_in.tag    = arbitrated.tag;
    assign tagged_in.epoch  = arbitrated.epoch;
    assign arbitrated.ready = tagged_in.ready;

    skid #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH + N_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) skid (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(tagged_in),
        .out_ch(tagged_out)
    );

    assign out_ch.addr = tagged_out.addr;
    assign {out_ch.data, data_out_sel} = tagged_out.data;
    assign out_ch.valid = tagged_out.valid;
    assign out_ch.tag = tagged_out.tag;
    assign out_ch.epoch = tagged_out.epoch;
    assign tagged_out.ready = out_ch.ready;
endmodule
