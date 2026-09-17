module hs_prod #(
    BASE_NUM = 0,
    VALID_COUNTER_START = 0,
    VALID_COUNTER_NUM = 60
) (
    input logic clk,

    rv_if.source out_ch
);
    assign out_ch.addr = '0;

    logic desire;
    logic handshaked;
    logic update;

    logic [31:0] counter = BASE_NUM;
    logic [31:0] valid_counter = VALID_COUNTER_START;

    initial begin
        desire = 1;
        out_ch.valid = 0;
    end

    assign handshaked = out_ch.valid && out_ch.ready;
    assign update = desire && (handshaked || !out_ch.valid);

    always @(posedge clk) begin
        valid_counter <= valid_counter + 1;
        if (valid_counter >= VALID_COUNTER_NUM) begin
            valid_counter <= 0;

            desire = !desire;
        end
    end

    always @(posedge clk) begin

        // Output Consume
        if (handshaked) begin
            out_ch.valid <= 0;
        end

        // Data Provide
        if (update) begin
            out_ch.valid   <= 1;
            out_ch.data    <= counter;
            counter <= counter + 1;
        end
    end

endmodule
