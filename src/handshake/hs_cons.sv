module hs_cons (
    input logic clk,

    rv_if.sink in_ch
);

    logic handshaked;
    assign handshaked = in_ch.valid && in_ch.ready;

    logic [31:0] ready_counter = 0;
    localparam counter = 50;

    initial begin
        in_ch.ready = 1;
    end

    always @(posedge clk) begin
        // $display("%0d in_ch.ready=%0d", $time, in_ch.ready);

        // Ready opposite
        if (ready_counter < counter) begin
            ready_counter <= ready_counter + 1;
        end else begin
            in_ch.ready   <= !in_ch.ready;
            // $display("%0d Ready changed now = %0d, (V=%0d, R=%0d)", $time, !in_ch.ready, in_ch.valid, !in_ch.ready);
            ready_counter <= 0;
        end

        // Handhsake
        // $display("---");
        if (handshaked) begin
            $display("%0d Data captured: %0d (V=%0d, R=%0d)", $time, in_ch.data, in_ch.valid,
                     in_ch.ready);
        end
    end

endmodule
;
