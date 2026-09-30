module sch_execute_mul_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    logic restart = 0;
    logic host_reg_write = 0;
    logic [4:0] host_reg_addr = 0;
    logic [31:0] host_reg_data = 0;
    logic [3:0] current_epoch = 1;
    logic branch_taken, halt, fault;
    logic [31:0] pc_target;
    logic [3:0] epoch_target;
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) mem_rsp();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(128)) vector_req();
    dma_ctrl_if #(.ADDR_WIDTH(32)) dma_ctrl[3]();

    for (genvar i = 0; i < 3; i++) begin
        assign dma_ctrl[i].ready = 1'b1;
    end
    assign vector_req.ready = 1'b1;

    sch_execute dut (
        .clk(clk), .rst_n(rst_n), .running(1'b1), .restart(restart),
        .host_reg_write(host_reg_write), .host_reg_addr(host_reg_addr),
        .host_reg_data(host_reg_data), .current_epoch(current_epoch),
        .mem_read_rsp(mem_rsp), .dma_ctrl(dma_ctrl),
        .vector_control_req(vector_req), .branch_taken(branch_taken),
        .pc_target(pc_target), .epoch_target(epoch_target),
        .halt(halt), .fault(fault)
    );

    function automatic logic [31:0] enc(
        input logic [4:0] op, input logic use_imm, input logic [4:0] rd,
        input logic [4:0] rs0, input logic [4:0] rs1, input logic [10:0] imm
    );
        return {op, use_imm, rd, rs0, rs1, imm};
    endfunction

    task automatic host_write(input logic [4:0] addr, input logic [31:0] data);
        @(negedge clk);
        host_reg_addr = addr;
        host_reg_data = data;
        host_reg_write = 1;
        @(negedge clk);
        host_reg_write = 0;
    endtask

    task automatic send_instr(input logic [31:0] pc, input logic [31:0] instr);
        @(negedge clk);
        mem_rsp.addr = pc;
        mem_rsp.data = instr;
        mem_rsp.epoch = current_epoch;
        mem_rsp.valid = 1;
        do @(posedge clk); while (!mem_rsp.ready);
        @(negedge clk);
        mem_rsp.valid = 0;
    endtask

    task automatic wait_retired;
        wait (dut.wb_valid);
        @(posedge clk);
        @(negedge clk);
    endtask

    initial begin
        mem_rsp.valid = 0;
        mem_rsp.addr = 0;
        mem_rsp.data = 0;
        mem_rsp.tag = 0;
        mem_rsp.epoch = current_epoch;
        repeat (3) @(negedge clk);
        rst_n = 1;
        host_write(5'd1, 32'h8001_2345);
        host_write(5'd2, 32'hffff_fffd);

        send_instr(32'h100, enc(5'd1, 0, 5'd3, 5'd1, 5'd2, 0));
        if (mem_rsp.ready) $fatal(1, "MUL did not stall instruction intake");
        wait_retired();
        if (dut.gpr[3] !== 32'h7ffc_9631)
            $fatal(1, "register MUL mismatch: %h", dut.gpr[3]);

        send_instr(32'h104, enc(5'd1, 1, 5'd4, 5'd1, 0, 11'h7ff));
        wait_retired();
        if (dut.gpr[4] !== 32'h7ffe_dcbb)
            $fatal(1, "immediate MUL mismatch: %h", dut.gpr[4]);

        send_instr(32'h108, enc(5'd0, 0, 5'd5, 5'd3, 5'd4, 0));
        wait_retired();
        if (dut.gpr[5] !== 32'hfffb_72ec)
            $fatal(1, "dependent ADD mismatch: %h", dut.gpr[5]);

        send_instr(32'h10c, enc(5'd1, 0, 5'd6, 5'd1, 5'd2, 0));
        current_epoch = 2;
        wait_retired();
        if (dut.gpr[6] !== 0)
            $fatal(1, "stale-epoch MUL wrote a register");

        send_instr(32'h110, enc(5'd1, 0, 5'd7, 5'd1, 5'd2, 0));
        restart = 1;
        @(negedge clk);
        restart = 0;
        repeat (4) @(negedge clk);
        if (dut.gpr[7] !== 0 || dut.wb_valid || dut.mul_operands_valid ||
            dut.mul_products_valid)
            $fatal(1, "restart did not cancel MUL");

        $display("sch_execute_mul_tb PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "sch_execute_mul_tb timeout");
    end
endmodule
