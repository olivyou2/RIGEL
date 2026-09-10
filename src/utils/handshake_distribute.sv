module handshake_distribute#(
    parameter N = 4
)(
    input logic valid,
    output logic ready,

    output logic out_valid[N],
    input logic out_ready[N]
);

    always @(*) begin
        for (int i=0; i<N; i++) begin
            if (i == 0) ready = out_ready[i];
            else ready = ready && out_ready[i];

            out_valid[i] = valid;
        end
    end

endmodule