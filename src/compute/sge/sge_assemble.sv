module sge_assemble #(
    parameter DATA_WIDTH = 64,
    parameter REG_SIZE   = 128
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink data_ch,

    rv_if.source reg_ch
);
    assign reg_ch.addr = '0;

    initial begin
        if (REG_SIZE % DATA_WIDTH != 0) begin
            $fatal(0, "reg size must be data_width 의 배수");
        end
    end

    localparam DATA_REPS = REG_SIZE / DATA_WIDTH;

    logic [$clog2(DATA_REPS + 1)-1:0] counter;
    logic [REG_SIZE-1:0] reg_set;
    logic [REG_SIZE-1:0] reg_set_next;

    assign data_ch.ready = !reg_ch.valid || reg_ch.ready;

    always_comb begin
        reg_set_next = reg_set;
        reg_set_next[DATA_WIDTH*counter+:DATA_WIDTH] = data_ch.data;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 0;
            reg_set <= 0;

            reg_ch.valid <= 0;
        end else begin
            if (reg_ch.valid && reg_ch.ready) begin
                reg_ch.valid <= 0;
            end

            if (data_ch.valid && data_ch.ready) begin
                reg_set <= reg_set_next;

                if (counter == DATA_REPS - 1) begin
                    reg_ch.data <= reg_set_next;
                    reg_ch.valid <= 1;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

endmodule
