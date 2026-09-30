// Scheduler control processor. The IXC selects this device with address[19:18]
// and forwards the full address. Decode the local address[17:0] here.
// Host writes registers at local offsets 0x00..0x44 and FIRE at 0x80.
// Instruction memory returns {addr, epoch} with data[31:0] as the instruction.
module sch #(
    parameter int SRC_DMA_BEAT_BYTES = 16
)(
    input logic clk,
    input logic rst_n,
    rv_if.sink write_req,
    rv_if.source mem_read_req,
    rv_if.sink mem_read_rsp,
    dma_ctrl_if.source dma_ctrl[3],
    rv_if.source vector_control_req,
    output logic running,
    output logic fault
);
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(mem_read_rsp.DATA_WIDTH),
            .TAG_WIDTH(mem_read_rsp.TAG_WIDTH), .EPOCH_WIDTH(4)) filtered_rsp();
    logic [3:0] current_epoch;
    logic branch_taken, exec_branch_taken;
    logic [31:0] pc_target, exec_pc_target;
    logic [3:0] epoch_target, exec_epoch_target;
    logic exec_fault, host_fault, halt;
    logic write_fire, host_fire, host_reg_write, invalid_write;
    logic [17:0] host_offset;

    assign host_offset = write_req.addr[17:0];
    assign write_req.ready = rst_n && !running;
    assign write_fire = write_req.valid && write_req.ready;
    assign host_fire = write_fire && host_offset == 18'h80 &&
                       write_req.data[1:0] == 2'b00;
    assign host_reg_write = write_fire && host_offset <= 18'h44 &&
                            host_offset[1:0] == 2'b00;
    assign invalid_write = write_fire && !host_fire && !host_reg_write;
    assign fault = host_fault || exec_fault;
    assign branch_taken = host_fire || exec_branch_taken;
    assign pc_target = host_fire ? write_req.data[31:0] : exec_pc_target;
    assign epoch_target = host_fire ? current_epoch + 4'd1 : exec_epoch_target;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            running <= 1'b0;
            host_fault <= 1'b0;
        end else begin
            if (invalid_write) host_fault <= 1'b1;
            if (host_fire) begin
                running <= 1'b1;
                host_fault <= 1'b0;
            end else if (running && (halt || exec_fault)) begin
                running <= 1'b0;
            end
        end
    end

    logic enable = 1;

    sch_fetch fetch (
        .clk(clk), .rst_n(rst_n), .mem_read_req(mem_read_req),
        .enable(enable && running && !fault),
        .branch_taken(branch_taken), .pc_target(pc_target),
        .epoch_target(epoch_target), .current_epoch(current_epoch)
    );

    sch_epoch_filter epoch_filter (
        .clk(clk), .rst_n(rst_n), .upstream(mem_read_rsp),
        .downstream(filtered_rsp), .epoch(current_epoch)
    );

    sch_execute #(.SRC_DMA_BEAT_BYTES(SRC_DMA_BEAT_BYTES)) execute (
        .clk(clk), .rst_n(rst_n), .running(running), .restart(host_fire),
        .host_reg_write(host_reg_write), .host_reg_addr(host_offset[6:2]),
        .host_reg_data(write_req.data[31:0]), .current_epoch(current_epoch),
        .mem_read_rsp(filtered_rsp), .dma_ctrl(dma_ctrl),
        .vector_control_req(vector_control_req),
        .branch_taken(exec_branch_taken), .pc_target(exec_pc_target),
        .epoch_target(exec_epoch_target), .halt(halt), .fault(exec_fault)
    );
endmodule
