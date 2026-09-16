module sge_control#(
    ADDR_WIDTH  = 32,
    DATA_WIDTH  = 64,
    REG_SIZE    = 128,
    BATCH_MAX   = 512
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] sge_base_addr,
    input logic [$clog2(BATCH_MAX):0] sge_batch_size,
    input logic sge_valid,
    output logic sge_ready,

    output logic [ADDR_WIDTH-1: 0] read_req_addr,
    output logic read_req_valid,
    input logic read_req_ready,

    input logic sge_handshaked,
    input logic backend_ready
);

    logic [1:0] fsm_status;

    localparam [1:0] FSM_IDLE = 0;
    localparam [1:0] FSM_WORK = 1;
    localparam [1:0] FSM_WAIT = 2;

    localparam  REPS_PER_BATCH = REG_SIZE / DATA_WIDTH;


    logic [ADDR_WIDTH-1:0] sge_base_addr_reg;
    logic [$clog2(BATCH_MAX):0] sge_batch_size_reg;
    logic [$clog2(BATCH_MAX):0] sge_batch_count_reg;

    logic [1:0] counter_fsm_status;
    logic [$clog2(BATCH_MAX):0] counter_batch_size_reg;
    logic [$clog2(BATCH_MAX):0] counter_batch_count_reg;


    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_status <= FSM_IDLE;
            read_req_valid <= 0;
        end else begin
            case (fsm_status)
                FSM_IDLE: begin
                    if (sge_ready && sge_valid) begin
                        sge_base_addr_reg       <= sge_base_addr;
                        sge_batch_size_reg      <= REPS_PER_BATCH * sge_batch_size;
                        sge_batch_count_reg     <= 0;

                        read_req_valid <= 1;
                        read_req_addr <= sge_base_addr;
                        
                        fsm_status <= FSM_WORK;
                    end
                end

                FSM_WORK: begin
                    if (read_req_valid && read_req_ready) begin
                        if (sge_batch_count_reg == sge_batch_size_reg - 1) begin
                            // 현재 beat가 마지막 beat
                            read_req_valid <= 0;
                            fsm_status <= FSM_WAIT;
                        end else begin
                            sge_batch_count_reg <= sge_batch_count_reg + 1;
                            read_req_addr <= read_req_addr + (DATA_WIDTH / 8);
                        end
                    end
                end

                FSM_WAIT: begin
                    if (counter_fsm_status == FSM_IDLE) begin
                        fsm_status <= FSM_IDLE;
                    end
                end

                default begin
                    
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            counter_fsm_status <= FSM_IDLE;
        end else begin
            case (counter_fsm_status) 
                FSM_IDLE: begin
                    if (sge_ready && sge_valid) begin
                        counter_fsm_status <= FSM_WORK;

                        counter_batch_size_reg <= sge_batch_size;
                        counter_batch_count_reg <= 0;
                    end
                end

                FSM_WORK: begin
                    if (counter_batch_count_reg == counter_batch_size_reg) begin
                        counter_fsm_status <= FSM_IDLE;
                    end

                    if (sge_handshaked) begin
                        counter_batch_count_reg <= counter_batch_count_reg + 1;
                    end
                end

                default: begin end
            endcase
        end
    end


    assign sge_ready = fsm_status == FSM_IDLE && counter_fsm_status == FSM_IDLE && backend_ready;
endmodule
