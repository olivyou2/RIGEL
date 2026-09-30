module vector_command_scheduler(
    input logic clk,
    input logic rst_n,

    // Module Interface
    rv_if.sink write_req,

    rv_if.sink read_req,
    rv_if.source read_rsp,

    // Command BRAM request
    rv_if.source bram_read_req,
    rv_if.sink bram_read_rsp
);

endmodule;