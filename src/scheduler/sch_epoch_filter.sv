module sch_epoch_filter(
    input logic clk,
    input logic rst_n,

    rv_if.sink upstream,
    rv_if.source downstream,

    input logic [upstream.EPOCH_WIDTH-1: 0] epoch
);

    logic upstream_handshaked;
    logic downstream_handshaked;

    assign upstream_handshaked = upstream.valid && upstream.ready;
    assign downstream_handshaked = downstream.valid && downstream.ready;

    logic requestable;

    assign requestable = !downstream.valid || downstream.ready;

    rv_if #(
        .ADDR_WIDTH (upstream.ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH (upstream.DATA_WIDTH /* default 128 */),
        .TAG_WIDTH  (upstream.TAG_WIDTH /* default 4 */),
        .EPOCH_WIDTH(upstream.EPOCH_WIDTH /* default 4 */)
     ) skid_if ();

    always @(posedge clk) begin
        if (!rst_n) begin
            downstream.valid <= 0;
            upstream.ready <= 1;
            skid_if.valid <= 0;
        end else begin
            if (downstream_handshaked) begin
                downstream.valid <= 0;
            end

            if (requestable) begin
                if (skid_if.valid) begin
                    if (skid_if.epoch == epoch) begin
                        downstream.valid <= 1;
                        downstream.addr <= skid_if.addr;
                        downstream.data <= skid_if.data;
                        downstream.epoch <= skid_if.epoch;
                        downstream.tag <= skid_if.tag;
                    end

                    skid_if.valid <= 0;
                    upstream.ready <= 1;
                end else if (upstream_handshaked && upstream.epoch == epoch) begin
                    downstream.valid <= 1;
                    downstream.addr <= upstream.addr;
                    downstream.data <= upstream.data;
                    downstream.epoch <= upstream.epoch;
                    downstream.tag <= upstream.tag;
                end
            end else begin
                if (upstream_handshaked && upstream.epoch == epoch) begin
                    skid_if.addr <= upstream.addr;
                    skid_if.data <= upstream.data;
                    skid_if.epoch <= upstream.epoch;
                    skid_if.tag <= upstream.tag;

                    skid_if.valid <= 1;
                    upstream.ready <= 0;
                end
            end
        end
    end

endmodule;