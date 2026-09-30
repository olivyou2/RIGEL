module sch_execute #(
    parameter int SRC_DMA_BEAT_BYTES = 16
)(
    input logic clk,
    input logic rst_n,
    input logic running,
    input logic restart,
    input logic host_reg_write,
    input logic [4:0] host_reg_addr,
    input logic [31:0] host_reg_data,
    input logic [3:0] current_epoch,
    rv_if.sink mem_read_rsp,
    dma_ctrl_if.source dma_ctrl[3],
    rv_if.source vector_control_req,
    output logic branch_taken,
    output logic [31:0] pc_target,
    output logic [3:0] epoch_target,
    output logic halt,
    output logic fault
);
    // Kept local so the scheduler does not depend on the compiler's include path.
    typedef struct packed {
        logic [3:0]  epoch;
        logic [31:0] pc;
        logic [4:0]  opcode;
        logic [4:0]  rd;
        logic [31:0] result;
        logic        reg_write;
        logic        branch_taken;
        logic [31:0] branch_target;
        logic [1:0]  dma_id;
        logic [31:0] dma_src;
        logic [31:0] dma_length;
        logic [15:0] emit_word;
        logic [31:0] emit_count;
        logic [31:0] emit_base;
        logic [31:0] emit_step;
        logic        illegal;
    } sch_ex_wb;

    localparam logic [4:0] OP_ADD  = 5'd0;
    localparam logic [4:0] OP_MUL  = 5'd1;
    localparam logic [4:0] OP_AND  = 5'd2;
    localparam logic [4:0] OP_OR   = 5'd3;
    localparam logic [4:0] OP_XOR  = 5'd4;
    localparam logic [4:0] OP_SHL  = 5'd5;
    localparam logic [4:0] OP_SHR  = 5'd6;
    localparam logic [4:0] OP_BEQ  = 5'd7;
    localparam logic [4:0] OP_BNE  = 5'd8;
    localparam logic [4:0] OP_BGT  = 5'd9;
    localparam logic [4:0] OP_BLT  = 5'd10;
    localparam logic [4:0] OP_CPY  = 5'd11;
    localparam logic [4:0] OP_WAIT = 5'd12;
    localparam logic [4:0] OP_EMIT = 5'd13;
    localparam logic [4:0] OP_HALT = 5'd14;

    // Unified addresses: 0..15 GPR, 16 output base, 17 output step.
    logic [31:0] gpr [0:15];
    logic [31:0] output_base;
    logic [31:0] output_step;

    function automatic logic [31:0] reg_read(input logic [4:0] addr);
        if (addr < 5'd16) return gpr[addr[3:0]];
        if (addr == 5'd16) return output_base;
        if (addr == 5'd17) return output_step;
        return 32'b0;
    endfunction

    sch_ex_wb wb;
    sch_ex_wb decoded;
    logic wb_valid;
    logic [31:0] instr;
    logic [4:0] opcode, rd, rs0, rs1;
    logic use_imm;
    logic [10:0] imm;
    logic [31:0] src0, src1, operand, imm_signed, imm_unsigned;
    logic dma_ready [0:2];
    logic wb_current, wb_complete;
    logic [31:0] emit_remaining;
    logic [31:0] emit_addr;
    logic emit_fire;

    assign instr = mem_read_rsp.data[31:0];
    assign opcode = instr[31:27];
    assign use_imm = instr[26];
    assign rd = instr[25:21];
    assign rs0 = instr[20:16];
    assign rs1 = instr[15:11];
    assign imm = instr[10:0];
    assign src0 = reg_read(rs0);
    assign src1 = reg_read(rs1);
    assign imm_signed = {{21{imm[10]}}, imm};
    assign imm_unsigned = {21'b0, imm};
    assign mem_read_rsp.ready = rst_n && running && !fault && !wb_valid;

    for (genvar i = 0; i < 3; i++) begin : dma_ports
        assign dma_ctrl[i].valid = wb_valid && wb_current && !fault &&
                                   wb.opcode == OP_CPY && wb.dma_id == 2'(i);
        assign dma_ctrl[i].length = wb.dma_length;
        assign dma_ctrl[i].step = 32'(SRC_DMA_BEAT_BYTES);
        assign dma_ctrl[i].addr_src = wb.dma_src;
        assign dma_ctrl[i].addr_dst = 32'b0;
        assign dma_ready[i] = dma_ctrl[i].ready;
    end

    // The control word is broadcast to the vector ALU and accumulator. The
    // address travels with the accumulator side and becomes the result address.
    assign vector_control_req.valid = wb_valid && wb_current && !fault &&
                                      wb.opcode == OP_EMIT && emit_remaining != 0;
    assign vector_control_req.addr = emit_addr;
    assign vector_control_req.data = $bits(vector_control_req.data)'(wb.emit_word);
    assign vector_control_req.tag = '0;
    assign vector_control_req.epoch = '0;
    assign emit_fire = vector_control_req.valid && vector_control_req.ready;

    always_comb begin
        decoded = '0;
        decoded.epoch = mem_read_rsp.epoch;
        decoded.pc = mem_read_rsp.addr[31:0];
        decoded.opcode = opcode;
        decoded.rd = rd;
        decoded.dma_id = imm[1:0];
        decoded.dma_src = src0;
        decoded.dma_length = src1;
        decoded.emit_word = src0[15:0];
        decoded.emit_count = src1;
        decoded.emit_base = output_base;
        decoded.emit_step = output_step;
        operand = use_imm ? imm_signed : src1;

        case (opcode)
            OP_ADD: begin decoded.reg_write = 1'b1; decoded.result = src0 + operand; end
            OP_MUL: begin decoded.reg_write = 1'b1; decoded.result = src0 * operand; end
            OP_AND: begin decoded.reg_write = 1'b1; decoded.result = src0 & (use_imm ? imm_unsigned : src1); end
            OP_OR:  begin decoded.reg_write = 1'b1; decoded.result = src0 | (use_imm ? imm_unsigned : src1); end
            OP_XOR: begin decoded.reg_write = 1'b1; decoded.result = src0 ^ (use_imm ? imm_unsigned : src1); end
            OP_SHL: begin decoded.reg_write = 1'b1; decoded.result = src0 << (use_imm ? imm[4:0] : src1[4:0]); end
            OP_SHR: begin decoded.reg_write = 1'b1; decoded.result = src0 >> (use_imm ? imm[4:0] : src1[4:0]); end
            OP_BEQ: decoded.branch_taken = (src0 == src1);
            OP_BNE: decoded.branch_taken = (src0 != src1);
            OP_BGT: decoded.branch_taken = ($signed(src0) > $signed(src1));
            OP_BLT: decoded.branch_taken = ($signed(src0) < $signed(src1));
            OP_CPY, OP_WAIT: decoded.illegal = (imm > 11'd2);
            OP_EMIT: ;
            OP_HALT: ;
            default: decoded.illegal = 1'b1;
        endcase
        decoded.branch_target = decoded.pc + (imm_signed << 2);
        if (decoded.reg_write && rd > 5'd17) decoded.illegal = 1'b1;
    end

    assign wb_current = (wb.epoch == current_epoch);
    always_comb begin
        wb_complete = 1'b1;
        if (wb_valid && wb_current && !wb.illegal) begin
            if (wb.opcode == OP_CPY) wb_complete = dma_ready[wb.dma_id];
            if (wb.opcode == OP_WAIT) wb_complete = dma_ready[wb.dma_id];
            if (wb.opcode == OP_EMIT) wb_complete = (emit_remaining == 0);
        end
    end
    assign branch_taken = wb_valid && wb_current && wb_complete &&
                          !wb.illegal && wb.branch_taken;
    assign halt = wb_valid && wb_current && wb_complete &&
                  !wb.illegal && wb.opcode == OP_HALT;
    assign pc_target = wb.branch_target;
    assign epoch_target = current_epoch + 4'd1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wb_valid <= 1'b0;
            wb <= '0;
            fault <= 1'b0;
            output_base <= '0;
            output_step <= 32'(SRC_DMA_BEAT_BYTES);
            emit_remaining <= '0;
            emit_addr <= '0;
            for (int i = 0; i < 16; i++) gpr[i] <= '0;
        end else begin
            if (restart) begin
                wb_valid <= 1'b0;
                fault <= 1'b0;
                emit_remaining <= '0;
            end else if (wb_valid && wb_complete) begin
                wb_valid <= 1'b0;
                if (wb_current) begin
                    if (wb.illegal) fault <= 1'b1;
                    else if (wb.reg_write) begin
                        if (wb.rd < 5'd16) gpr[wb.rd[3:0]] <= wb.result;
                        else if (wb.rd == 5'd16) output_base <= wb.result;
                        else if (wb.rd == 5'd17) output_step <= wb.result;
                    end
                end
            end
            if (host_reg_write) begin
                if (host_reg_addr < 5'd16) gpr[host_reg_addr[3:0]] <= host_reg_data;
                else if (host_reg_addr == 5'd16) output_base <= host_reg_data;
                else if (host_reg_addr == 5'd17) output_step <= host_reg_data;
            end
            if (!restart && mem_read_rsp.valid && mem_read_rsp.ready &&
                mem_read_rsp.epoch == current_epoch) begin
                wb <= decoded;
                wb_valid <= 1'b1;
                emit_remaining <= decoded.emit_count;
                emit_addr <= decoded.emit_base;
            end else if (emit_fire) begin
                emit_remaining <= emit_remaining - 32'd1;
                emit_addr <= emit_addr + wb.emit_step;
            end
        end
    end
endmodule
