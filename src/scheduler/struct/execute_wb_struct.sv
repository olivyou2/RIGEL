// One decoded instruction held until its architectural effect completes.
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
