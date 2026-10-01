// Defined response for an address-mapped device without readable registers.
module rv_zero_read(
    input logic clk,
    input logic rst_n,
    rv_if.sink read_req,
    rv_if.source read_rsp
);
    logic [1:0] response_count;
    logic response_head, response_tail;
    logic [$bits(read_rsp.addr)-1:0] response_addr[2];
    logic [$bits(read_rsp.tag)-1:0] response_tag[2];
    logic [$bits(read_rsp.epoch)-1:0] response_epoch[2];

    // Registered occupancy isolates request ready from downstream response
    // ready, including an interconnect that uses both channels together.
    assign read_req.ready = rst_n && response_count < 2;
    assign read_rsp.valid = response_count != 0;
    assign read_rsp.data = '0;
    assign read_rsp.addr = response_addr[response_head];
    assign read_rsp.tag = response_tag[response_head];
    assign read_rsp.epoch = response_epoch[response_head];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            response_count <= '0;
            response_head <= 1'b0;
            response_tail <= 1'b0;
        end else begin
            if (read_req.valid && read_req.ready) begin
                response_addr[response_tail] <= read_req.addr;
                response_tag[response_tail] <= read_req.tag;
                response_epoch[response_tail] <= read_req.epoch;
                response_tail <= ~response_tail;
            end
            if (read_rsp.valid && read_rsp.ready)
                response_head <= ~response_head;
            case ({read_req.valid && read_req.ready,
                   read_rsp.valid && read_rsp.ready})
                2'b10: response_count <= response_count + 1'b1;
                2'b01: response_count <= response_count - 1'b1;
                default: ;
            endcase
        end
    end
endmodule
