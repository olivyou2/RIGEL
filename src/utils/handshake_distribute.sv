// Broadcast one ready/valid transaction to N independent destinations.
//
// Address and data remain owned by the input source until every destination
// has accepted the transaction.  The sent mask prevents a faster destination
// from accepting the same transaction more than once while another stalls.
module handshake_distribute #(
    parameter N = 2
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink in_ch,
    rv_if.source out_ch[N]
);
    logic [N-1:0] sent;
    logic [N-1:0] output_ready;
    logic [N-1:0] output_fire;
    logic input_fire;

    initial begin
        if (N < 1) $fatal(1, "handshake_distribute N must be positive");
    end

    for (genvar i = 0; i < N; i++) begin : outputs
        assign out_ch[i].addr  = in_ch.addr;
        assign out_ch[i].data  = in_ch.data;
        assign out_ch[i].valid = rst_n && in_ch.valid && !sent[i];
        assign output_ready[i] = out_ch[i].ready;
        assign output_fire[i]  = out_ch[i].valid && out_ch[i].ready;
    end

    assign in_ch.ready = rst_n && &(sent | output_ready);
    assign input_fire = in_ch.valid && in_ch.ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sent <= '0;
        end else if (input_fire) begin
            // Every destination has now accepted this transaction.  Clear in
            // time for all branches to observe the next input transaction.
            sent <= '0;
        end else begin
            sent <= sent | output_fire;
        end
    end
endmodule
