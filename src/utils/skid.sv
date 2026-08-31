module skid#(
    parameter DATA_WIDTH=96
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] input_data,
    input logic input_valid,
    output logic input_ready,

    output logic [DATA_WIDTH-1: 0] output_data,
    output logic output_valid,
    input logic output_ready
);

    logic skid_valid;
    logic [DATA_WIDTH-1:0] skid_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            skid_valid <= 0;
            skid_data <= 0;

            input_ready <= 1;
        end else begin
            if (input_valid && input_ready) begin
                
            end
        end
    end

endmodule