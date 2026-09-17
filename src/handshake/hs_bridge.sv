module hs_bridge (
    input logic clk,

    rv_if.sink in_ch,

    rv_if.source out_ch
);
    assign out_ch.addr = '0;

    logic [31:0] skid_data;
    logic skid_valid;

    initial begin
        in_ch.ready  = 1;
        out_ch.valid = 0;

        skid_data    = 0;
        skid_valid   = 0;
    end

    logic output_acceptable;
    assign output_acceptable = !out_ch.valid || (out_ch.valid && out_ch.ready);

    always @(posedge clk) begin
        // Output Consume
        if (out_ch.valid && out_ch.ready) begin
            out_ch.valid <= 0;
        end

        // Data Provide
        if (in_ch.valid && in_ch.ready) begin
            if (output_acceptable) begin
                out_ch.valid <= 1;
                out_ch.data  <= in_ch.data;
            end else begin
                in_ch.ready <= 0;
                skid_data   <= in_ch.data;
                skid_valid  <= 1;
            end
        end else if (skid_valid) begin

            if (output_acceptable) begin
                out_ch.valid <= 1;
                out_ch.data  <= skid_data;

                skid_valid   <= 0;
                in_ch.ready  <= 1;
            end

        end
    end

endmodule
