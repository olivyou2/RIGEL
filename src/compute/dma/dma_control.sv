module dma_control#(
    parameter ADDR_WIDTH = 32
)(
    input logic clk,
    input logic rst_n,

    input logic fire_valid,
    output logic fire_ready,

    input logic [ADDR_WIDTH-1: 0] fire_addr_src,
    input logic [ADDR_WIDTH-1: 0] fire_addr_dst,
    input logic [ADDR_WIDTH-1: 0] fire_step,
    input logic [ADDR_WIDTH-1: 0] fire_length,

    output logic addr_rst,
    output logic [ADDR_WIDTH-1: 0]  addr_rst_src,
    output logic [ADDR_WIDTH-1: 0]  addr_rst_dst,
    output logic [ADDR_WIDTH-1: 0]  addr_rst_step,

    output logic addr_src_valid,
    input logic addr_src_ready,

    input logic dma_dataout_handshake
);

    logic [1:0] issue_fsm_state;
    logic [1:0] counter_fsm_state;

    logic [ADDR_WIDTH-1: 0] fire_addr_src_reg;
    logic [ADDR_WIDTH-1: 0] fire_addr_dst_reg;
    logic [ADDR_WIDTH-1: 0] fire_step_reg;
    logic [ADDR_WIDTH-1: 0] fire_length_reg;
    logic [ADDR_WIDTH-1: 0] fire_counter_reg;

    logic [ADDR_WIDTH-1: 0] counter_step_reg;
    logic [ADDR_WIDTH-1: 0] counter_length_reg;
    logic [ADDR_WIDTH-1: 0] counter_counter_reg;

    localparam [1:0] FSM_IDLE = 0;
    localparam [1:0] FSM_STARTUP = 1;
    localparam [1:0] FSM_WORK = 2;
    localparam [1:0] FSM_WAIT = 3;

    assign fire_ready = issue_fsm_state == FSM_IDLE && counter_fsm_state == FSM_IDLE;

    // Issue FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            issue_fsm_state <= 0;

            addr_src_valid <= 0;
            addr_rst <= 0;
        end else begin
            addr_rst <= 0;

            case (issue_fsm_state)
                FSM_IDLE: begin
                    if (fire_valid && fire_ready) begin
                        issue_fsm_state <= FSM_STARTUP;

                        fire_addr_src_reg <= fire_addr_src;
                        fire_addr_dst_reg <= fire_addr_dst;
                        fire_step_reg <= fire_step;
                        fire_length_reg <= fire_length;
                        fire_counter_reg <= 0;

                        if (fire_length == 0 || fire_step == 0) begin
                            issue_fsm_state <= FSM_IDLE;
                        end
                    end
                end

                FSM_STARTUP: begin
                    issue_fsm_state <= FSM_WORK;

                    addr_rst <= 1;
                    addr_rst_src <= fire_addr_src_reg;
                    addr_rst_dst <= fire_addr_dst_reg;
                    addr_rst_step <= fire_step_reg;
                end

                FSM_WORK: begin
                    addr_src_valid <= 1;

                    if (addr_src_valid && addr_src_ready) begin
                        fire_counter_reg <= fire_counter_reg + fire_step_reg;

                        if (fire_counter_reg + fire_step_reg >= fire_length_reg) begin
                            issue_fsm_state <= FSM_WAIT;
                            addr_src_valid <= 0;
                        end
                    end
                end

                FSM_WAIT: begin
                    if (counter_fsm_state == FSM_IDLE) begin
                        $display("[DMA] dma process done");

                        issue_fsm_state <= FSM_IDLE;
                    end
                end

                default: begin
                end
            endcase
        end
    end

    // DMA Dataout count FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            counter_fsm_state <= 0;
        end else begin
            case (counter_fsm_state)
                FSM_IDLE: begin
                    if (fire_valid && fire_ready) begin
                        counter_fsm_state <= FSM_WORK;

                        counter_step_reg <= fire_step;
                        counter_length_reg <= fire_length;
                        counter_counter_reg <= 0;

                        if (fire_length == 0 || fire_step == 0) begin
                            counter_fsm_state <= FSM_IDLE;
                        end
                    end
                end

                FSM_WORK: begin
                    if (dma_dataout_handshake) begin
                        counter_counter_reg <= counter_counter_reg + counter_step_reg;
                        if (counter_counter_reg + counter_step_reg >= counter_length_reg) begin
                            counter_fsm_state <= FSM_IDLE;
                        end
                    end
                end

                default: counter_fsm_state <= FSM_IDLE;
            endcase
        end
    end

endmodule