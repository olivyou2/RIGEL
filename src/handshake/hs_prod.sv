module hs_prod(
    input logic clk,

    output logic [31:0] data,
    output logic valid,
    input logic ready
);

    logic desire;
    logic handshaked;
    logic update;

    logic [31:0] counter = 1;
    logic [31:0] valid_counter = 0;

    initial begin
        desire = 1;
        valid = 0;
    end

    assign handshaked = valid && ready;
    assign update = desire && (handshaked || !valid);

    localparam valid_counter_num = 60;

    always @(posedge clk) begin
        valid_counter <= valid_counter + 1;
        if (valid_counter >= valid_counter_num) begin
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