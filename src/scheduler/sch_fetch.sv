module sch_fetch #(
    parameter int PC_WIDTH = 32,
    parameter int EPOCH_WIDTH = 4,
    parameter int PC_STEP = 4
)(
    input logic clk,
    input logic rst_n,
    rv_if.source mem_read_req,
    input logic enable,
    input logic branch_taken,
    input logic [PC_WIDTH-1:0] pc_target,
    input logic [EPOCH_WIDTH-1:0] epoch_target,
    output logic [EPOCH_WIDTH-1:0] current_epoch
);
    logic [PC_WIDTH-1:0] pc;
    logic [EPOCH_WIDTH-1:0] epoch;

    assign current_epoch = epoch;
    assign mem_read_req.data = '0;
    assign mem_read_req.tag = '0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc <= '0;
            epoch <= '0;
            mem_read_req.valid <= 1'b0;
            mem_read_req.addr <= '0;
            mem_read_req.epoch <= '0;
        end else begin
            // A stalled request retains its payload even across a redirect.
            if (mem_read_req.valid && mem_read_req.ready)
                mem_read_req.valid <= 1'b0;

            if (branch_taken) begin
                pc <= pc_target;
                epoch <= epoch_target;
            end else if (enable && (!mem_read_req.valid || mem_read_req.ready)) begin
                mem_read_req.valid <= 1'b1;
                mem_read_req.addr <= pc;
                mem_read_req.epoch <= epoch;
                pc <= pc + PC_WIDTH'(PC_STEP);
            end
        end
    end
endmodule
