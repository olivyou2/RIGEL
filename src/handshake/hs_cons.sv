module hs_cons(
    input logic clk,
    
    input logic [31:0] data,
    input logic valid,
    output logic ready
);

    logic handshaked;
    assign handshaked = valid && ready;

    logic [31:0] ready_counter = 0;
    localparam counter = 50;

    initial begin
        ready = 1;
    end

    always @(posedge clk) begin
        // $display("%0d ready=%0d", $time, ready);

        // Ready opposite
        if (ready_counter < counter) begin
            ready_counter <= ready_counter + 1;
        end else begin
            ready <= !ready;
            // $display("%0d Ready changed now = %0d, (V=%0d, R=%0d)", $time, !ready, valid, !ready);
            ready_counter <= 0;
        end

        // Handhsake
        // $display("---");
        if (handshaked) begin
            $display("%0d Data captured: %0d (V=%0d, R=%0d)", $time, data, valid, ready);
        end
    end

endmodule;