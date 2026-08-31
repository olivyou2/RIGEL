module arbitation#(
    parameter DATA_WIDTH=96,
    parameter CHANNELS=2
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] data_in[CHANNELS],
    input logic data_in_valid[CHANNELS],
    output logic data_in_ready[CHANNELS],

    output logic [DATA_WIDTH-1:0] data_out,
    output logic data_out_valid,
    input logic data_out_ready
);
    localparam CHANNEL_WIDTH = $clog2(CHANNELS);

    logic [CHANNEL_WIDTH-1: 0] select;

    always @(*) begin
        for (int i=0; i<CHANNELS; i++) begin
            if (data_in_valid[i]) begin
                select = i;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
        end else begin
            for (int i=0; i<CHANNELS; i++) begin
                data_in_ready[select] <= 0;
            end

            if (data_out_valid && data_out_ready) begin
                data_out_valid <= 0;
            end

            if (!data_out_valid || (data_out_valid && data_out_ready)) begin
                if (data_in_valid[select]) begin
                    data_in_ready[select] <= 1;

                    data_out_valid <= 1;
                    data_out <= data_in[select];
                end
            end
        end
    end

endmodule