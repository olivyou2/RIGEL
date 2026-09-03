module hs_prod#(BASE_NUM=0, VALID_COUNTER_START=0, VALID_COUNTER_NUM=60)(
    input logic clk,

    output logic [31:0] data,
    output logic valid,
    input logic ready
);

    logic desire;
    logic handshaked;
    logic update;

    logic [31:0] counter = BASE_NUM;
    logic [31:0] valid_counter = VALID_COUNTER_START;

    initial begin
        desire = 1;
        valid = 0;
    end

    assign handshaked = valid && ready;
    assign update = desire && (handshaked || !valid);

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
            valid   <= 0;
        end

        // Data Provide
        if (update) begin
            valid   <= 1;
            data    <= counter;
            counter <= counter + 1;
        end
    end

endmodule