module arbitation #(
    parameter DATA_WIDTH = 96,
    parameter CHANNELS   = 2
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink in_ch[CHANNELS],

    rv_if.source out_ch
);
    logic [DATA_WIDTH-1:0] data_in[CHANNELS];
    logic data_in_valid[CHANNELS];
    logic data_in_ready[CHANNELS];
    for (genvar ch_idx = 0; ch_idx < $size(data_in_valid); ch_idx++) begin : map_in_ch
        assign data_in[ch_idx] = in_ch[ch_idx].data;
        assign data_in_valid[ch_idx] = in_ch[ch_idx].valid;
        assign in_ch[ch_idx].ready = data_in_ready[ch_idx];
    end
    assign out_ch.addr = '0;

    localparam CHANNEL_WIDTH = $clog2(CHANNELS);

    logic [CHANNEL_WIDTH-1:0] select;

    always @(*) begin
        for (int i = 0; i < CHANNELS; i++) begin
            if (data_in_valid[i]) begin
                select = i;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
        end else begin
            for (int i = 0; i < CHANNELS; i++) begin
                data_in_ready[select] <= 0;
            end

            if (out_ch.valid && out_ch.ready) begin
                out_ch.valid <= 0;
            end

            if (!out_ch.valid || (out_ch.valid && out_ch.ready)) begin
                if (data_in_valid[select]) begin
                    data_in_ready[select] <= 1;

                    out_ch.valid <= 1;
                    out_ch.data <= data_in[select];
                end
            end
        end
    end

endmodule
