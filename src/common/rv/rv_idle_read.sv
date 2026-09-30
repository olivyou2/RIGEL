// Tie off an unused read port, while always draining any response.
module rv_idle_read(
    rv_if.source read_req,
    rv_if.sink read_rsp
);
    assign read_req.valid = 1'b0;
    assign read_req.addr = '0;
    assign read_req.data = '0;
    assign read_req.tag = '0;
    assign read_req.epoch = '0;
    assign read_rsp.ready = 1'b1;
endmodule
