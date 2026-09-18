// N->1 arbiter

module arbiter #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 32,
    parameter N = 2
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink in_ch[N],

    rv_if.source out_ch,

    output logic [$clog2(N)-1:0] data_out_sel
);
    logic [DATA_WIDTH-1:0] data_in[N];
    logic [ADDR_WIDTH-1:0] addr_in[N];
    logic data_valid[N];
    logic data_ready[N];
    for (genvar ch_idx = 0; ch_idx < $size(data_valid); ch_idx++) begin : map_in_ch
        assign data_in[ch_idx] = in_ch[ch_idx].data;
        assign addr_in[ch_idx] = in_ch[ch_idx].addr;
        assign data_valid[ch_idx] = in_ch[ch_idx].valid;
        assign in_ch[ch_idx].ready = data_ready[ch_idx];
    end

    localparam N_WIDTH = $clog2(N);

    initial begin
        if (N <= 0 || (N & (N - 1)) != 0) $fatal(1, "N (%0d) must be a power of 2", N);

        if (N == 1) $fatal(1, "N must be greater than 1");
    end

    logic [N_WIDTH-1:0] robin_idx = 0;

    logic [N_WIDTH-1:0] crop_i;
    logic [N_WIDTH-1:0] select;
    logic               select_valid;

    logic               data_out_handshaked;
    assign data_out_handshaked = out_ch.valid && out_ch.ready;

    logic writable;
    assign writable = !out_ch.valid || data_out_handshaked;

    always_comb begin
        select = 0;
        select_valid = 0;

        for (logic [N_WIDTH:0] i = 0; i < N; i++) begin
            data_ready[i] = 0;
            crop_i = i + robin_idx;

            if (!select_valid && data_valid[crop_i]) begin
                select = crop_i;
                select_valid = 1;
            end
        end

        if (select_valid && writable) begin
            data_ready[select] = 1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            robin_idx <= 0;
            out_ch.valid <= 0;
        end else begin
            if (data_out_handshaked) begin
                out_ch.valid <= 0;
            end

            if (select_valid && writable) begin
                out_ch.valid <= 1;
                data_out_sel <= select;
                out_ch.data <= data_in[select];
                out_ch.addr <= addr_in[select];

                robin_idx <= select + 1;
            end
        end
    end

    initial begin
        out_ch.valid = 0;
    end

endmodule
