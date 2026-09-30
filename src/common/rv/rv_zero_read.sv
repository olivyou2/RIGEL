// Defined response for an address-mapped device without readable registers.
module rv_zero_read(
    input logic clk,
    input logic rst_n,
    rv_if.sink read_req,
    rv_if.source read_rsp
);
    assign read_req.ready = rst_n && (!read_rsp.valid || read_rsp.ready);
    assign read_rsp.data = '0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_rsp.valid <= 1'b0;
            read_rsp.addr <= '0;
            read_rsp.tag <= '0;
            read_rsp.epoch <= '0;
        end else if (read_req.valid && read_req.ready) begin
            read_rsp.valid <= 1'b1;
            read_rsp.addr <= read_req.addr;
            read_rsp.tag <= read_req.tag;
            read_rsp.epoch <= read_req.epoch;
        end else if (read_rsp.valid && read_rsp.ready) begin
            read_rsp.valid <= 1'b0;
        end
    end
endmodule
