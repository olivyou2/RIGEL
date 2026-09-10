module sge_assemble#(
    parameter DATA_WIDTH = 64,
    parameter REG_SIZE = 128
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] data_in,
    input logic data_valid,
    output logic data_ready,

    output logic [REG_SIZE-1: 0] reg_out,
    output logic reg_valid,
    input logic reg_ready
);

    initial begin
        if (REG_SIZE % DATA_WIDTH != 0) begin
            $fatal(0, "reg size must be data_width 의 배수");
        end
    end

    localparam DATA_REPS = REG_SIZE / DATA_WIDTH;

    logic [$clog2(DATA_REPS + 1)-1: 0] counter;
    logic [REG_SIZE-1: 0] reg_set;
    logic [REG_SIZE-1: 0] reg_set_next;

    assign data_ready = !reg_valid || reg_ready;

    always_comb begin
        reg_set_next = reg_set;
        reg_set_next[DATA_WIDTH * counter +: DATA_WIDTH] = data_in;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 0;
            reg_set <= 0;

            reg_valid <= 0;
        end else begin
            if (reg_valid && reg_ready) begin
                reg_valid <= 0;
            end

            if (data_valid && data_ready) begin
                reg_set <= reg_set_next;

                if (counter == DATA_REPS - 1) begin
                    reg_out <= reg_set_next;
                    reg_valid <= 1;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

endmodule