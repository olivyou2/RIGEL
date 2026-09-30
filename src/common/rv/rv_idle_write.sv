// Tie off an unused ready/valid write-request input.
module rv_idle_write(rv_if.source write_req);
    assign write_req.valid = 1'b0;
    assign write_req.addr = '0;
    assign write_req.data = '0;
    assign write_req.tag = '0;
    assign write_req.epoch = '0;
endmodule
