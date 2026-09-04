module skid#(
    parameter DATA_WIDTH = 64
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1:0] data_in,
    input logic data_in_valid,
    output logic data_in_ready,

    output logic [DATA_WIDTH-1:0] data_out,
    output logic data_out_valid,
    input logic data_out_ready
);
    logic [DATA_WIDTH-1:0] skid_data;
    logic skid_valid;

    initial begin
        data_in_ready   = 1;
        data_out_valid  = 0;

        skid_data       = 0;
        skid_valid      = 0;
    end

    logic output_acceptable;
    assign output_acceptable = !data_out_valid || (data_out_valid && data_out_ready);

    always @(posedge clk) begin
        if (!rst_n) begin
            data_out_valid <= 0;
            data_in_ready <= 1;
            skid_valid <= 0;
        end else begin
             // Output Consume
            if (data_out_valid && data_out_ready) begin
                data_out_valid <= 0;
            end

            // Data Provide
            if (data_in_valid && data_in_ready) begin
                if (output_acceptable) begin
                    data_out_valid <= 1;
                    data_out <= data_in;
                end else begin
                    data_in_ready <= 0;
                    skid_data <= data_in;
                    skid_valid <= 1;
                end
            end else if (skid_valid) begin

                if (output_acceptable) begin
                    data_out_valid <= 1;
                    data_out <= skid_data;

                    skid_valid <= 0;
                    data_in_ready <= 1;
                end

            end
        end
    end

endmodule