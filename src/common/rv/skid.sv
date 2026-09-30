module skid #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter TAG_WIDTH = 4,
    parameter EPOCH_WIDTH = 4
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink in_ch,

    rv_if.source out_ch
);
    logic [ADDR_WIDTH-1:0] skid_addr;
    logic [DATA_WIDTH-1:0] skid_data;
    logic [TAG_WIDTH-1:0] skid_tag;
    logic [EPOCH_WIDTH-1:0] skid_epoch;
    logic skid_valid;

    initial begin
        if ($bits(in_ch.addr) != ADDR_WIDTH) begin
            $fatal(1,
                   "skid input ADDR_WIDTH mismatch: parameter=%0d interface=%0d",
                   ADDR_WIDTH, $bits(in_ch.addr));
        end
        if ($bits(out_ch.addr) != ADDR_WIDTH) begin
            $fatal(1,
                   "skid output ADDR_WIDTH mismatch: parameter=%0d interface=%0d",
                   ADDR_WIDTH, $bits(out_ch.addr));
        end
        if ($bits(in_ch.data) != DATA_WIDTH) begin
            $fatal(1,
                   "skid input DATA_WIDTH mismatch: parameter=%0d interface=%0d",
                   DATA_WIDTH, $bits(in_ch.data));
        end
        if ($bits(out_ch.data) != DATA_WIDTH) begin
            $fatal(1,
                   "skid output DATA_WIDTH mismatch: parameter=%0d interface=%0d",
                   DATA_WIDTH, $bits(out_ch.data));
        end
        if ($bits(in_ch.tag) != TAG_WIDTH || $bits(out_ch.tag) != TAG_WIDTH)
            $fatal(1, "skid TAG_WIDTH mismatch");
        if ($bits(in_ch.epoch) != EPOCH_WIDTH || $bits(out_ch.epoch) != EPOCH_WIDTH)
            $fatal(1, "skid EPOCH_WIDTH mismatch");

        in_ch.ready  = 1;
        out_ch.valid = 0;

        skid_addr  = 0;
        skid_data  = 0;
        skid_tag   = 0;
        skid_epoch = 0;
        skid_valid = 0;
    end

    logic output_acceptable;
    assign output_acceptable = !out_ch.valid || (out_ch.valid && out_ch.ready);

    always @(posedge clk) begin
        if (!rst_n) begin
            out_ch.valid <= 0;
            in_ch.ready  <= 1;
            skid_valid   <= 0;
        end else begin
            // Output Consume
            if (out_ch.valid && out_ch.ready) begin
                out_ch.valid <= 0;
            end

            // Data Provide
            if (in_ch.valid && in_ch.ready) begin
                if (output_acceptable) begin
                    out_ch.valid <= 1;
                    out_ch.addr  <= in_ch.addr;
                    out_ch.data  <= in_ch.data;
                    out_ch.tag   <= in_ch.tag;
                    out_ch.epoch <= in_ch.epoch;
                end else begin
                    in_ch.ready <= 0;
                    skid_addr   <= in_ch.addr;
                    skid_data   <= in_ch.data;
                    skid_tag    <= in_ch.tag;
                    skid_epoch  <= in_ch.epoch;
                    skid_valid  <= 1;
                end
            end else if (skid_valid) begin

                if (output_acceptable) begin
                    out_ch.valid <= 1;
                    out_ch.addr  <= skid_addr;
                    out_ch.data  <= skid_data;
                    out_ch.tag   <= skid_tag;
                    out_ch.epoch <= skid_epoch;

                    skid_valid   <= 0;
                    in_ch.ready  <= 1;
                end

            end
        end
    end

endmodule
