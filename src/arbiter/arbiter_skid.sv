// N-to-1 data arbiter with a registered output and matching selection tag.
module arbiter_skid #(
    parameter DATA_WIDTH = 64,
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
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH)
    ) arbitrated ();
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH + N_WIDTH)
    ) tagged_in ();
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH + N_WIDTH)
    ) tagged_out ();

    arbiter #(
        .DATA_WIDTH(DATA_WIDTH),
        .N(N)
    ) arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(in_ch),
        .out_ch(arbitrated),
        .data_out_sel(selected)
    );

    assign tagged_in.addr   = '0;
    assign tagged_in.data   = {arbitrated.data, selected};
    assign tagged_in.valid  = arbitrated.valid;
    assign arbitrated.ready = tagged_in.ready;

    skid #(
        .DATA_WIDTH(DATA_WIDTH + N_WIDTH)
    ) skid (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(tagged_in),
        .out_ch(tagged_out)
    );

    assign out_ch.addr = '0;
    assign {out_ch.data, data_out_sel} = tagged_out.data;
    assign out_ch.valid = tagged_out.valid;
    assign tagged_out.ready = out_ch.ready;
endmodule
