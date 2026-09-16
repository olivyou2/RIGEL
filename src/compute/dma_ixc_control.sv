module dma_ixc_control#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,

    parameter DMA_N = 3
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] read_req_addr,
    input logic read_req_valid,
    output logic read_req_ready,

    output logic [DATA_WIDTH-1: 0] read_rsp_data,
    output logic read_rsp_valid,
    input logic read_rsp_ready,

    input logic [ADDR_WIDTH-1: 0] write_req_addr,
    input logic [DATA_WIDTH-1: 0] write_req_data,
    input logic write_req_valid,
    output logic write_req_ready,

    output logic [ADDR_WIDTH-1: 0] fire_length     [DMA_N],
    output logic [ADDR_WIDTH-1: 0] fire_step       [DMA_N],
    output logic [ADDR_WIDTH-1: 0] fire_addr_src   [DMA_N],
    output logic [ADDR_WIDTH-1: 0] fire_addr_dst   [DMA_N],

    output logic dma_fire[DMA_N],
    input logic dma_ready[DMA_N]
);

    logic [1:0] read_fsm;
    logic [1:0] write_fsm;

    logic [2:0] read_reg_idx;
    logic [2:0] read_dma_idx;

    assign read_reg_idx = read_req_addr[5:3];
    assign read_dma_idx = read_req_addr[8:6];

    logic [2:0] write_reg_idx;
    logic [2:0] write_dma_idx;

    assign write_reg_idx = write_req_addr[5:3];
    assign write_dma_idx = write_req_addr[8:6];

    localparam [1:0] FSM_IDLE = 0;
    localparam [1:0] FSM_READ_WAIT = 1;
    localparam [1:0] FSM_DMA_WAIT = 1;

    localparam REG_LENGTH       = 3'd0;
    localparam REG_STEP         = 3'd1;
    localparam REG_ADDR_SRC     = 3'd2;
    localparam REG_ADDR_DST     = 3'd3;
    localparam REG_FIRE         = 3'd4;
    localparam REG_IDLE         = 3'd5;

    assign read_req_ready = (read_fsm == FSM_IDLE);

    // Read FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            read_fsm <= 0;

            read_rsp_valid <= 0;
        end else begin
            case (read_fsm)
                FSM_IDLE: begin
                    if (read_req_ready && read_req_valid) begin
                        // 주소가 8B까지 확장될 여지가 있으므로
                        // ADDR_WIDTH[2:0] 는 0
                        // ADDR_WIDTH[5:3] 는 Reg Map
                        // ADDR_WIDTH[8:6] 는 DMA Index

                        read_fsm <= FSM_READ_WAIT;
                        read_rsp_valid <= 1;

                        case (read_reg_idx)
                            REG_LENGTH:     read_rsp_data <= fire_length[read_dma_idx];
                            REG_STEP:       read_rsp_data <= fire_step[read_dma_idx];
                            REG_ADDR_SRC:   read_rsp_data <= fire_addr_src[read_dma_idx];
                            REG_ADDR_DST:   read_rsp_data <= fire_addr_dst[read_dma_idx];
                            REG_IDLE:       read_rsp_data <= dma_ready[read_dma_idx];
                            default: read_rsp_data <= 0;
                        endcase
                    end
                end

                FSM_READ_WAIT: begin
                    if (read_rsp_valid && read_rsp_ready) begin
                        read_rsp_valid <= 0;
                        read_fsm <= FSM_IDLE;
                    end
                end

                default: begin
                    
                end
            endcase
        end
    end

    // Write FSM
    logic [$clog2(DMA_N): 0] last_fired_dma;

    assign write_req_ready = write_fsm == FSM_IDLE;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i=0; i<DMA_N; i++) begin
                fire_length[i] <= 0;
                fire_addr_dst[i] <= 0;
                fire_addr_src[i] <= 0;
                fire_step[i] <= 0;

                dma_fire[i] <= 0;
            end

            write_fsm <= FSM_IDLE;
            last_fired_dma <= 0;
        end else begin
            case (write_fsm)
                FSM_IDLE: begin
                    if (write_req_valid && write_req_ready) begin
                        case (write_reg_idx)
                            REG_LENGTH: begin
                                fire_length[write_dma_idx] <= write_req_data[ADDR_WIDTH-1: 0];
                            end

                            REG_STEP: begin
                                fire_step[write_dma_idx] <= write_req_data[ADDR_WIDTH-1: 0];
                            end

                            REG_ADDR_SRC: begin
                                fire_addr_src[write_dma_idx] <= write_req_data[ADDR_WIDTH-1: 0];
                            end

                            REG_ADDR_DST: begin
                                fire_addr_dst[write_dma_idx] <= write_req_data[ADDR_WIDTH-1: 0];
                            end

                            REG_FIRE: begin
                                dma_fire[write_dma_idx] <= 1;
                                last_fired_dma <= write_dma_idx;
                                write_fsm <= FSM_DMA_WAIT;
                            end

                            default: begin end
                        endcase
                    end
                end

                FSM_DMA_WAIT: begin
                    if (dma_fire[last_fired_dma] && dma_ready[last_fired_dma]) begin
                        dma_fire[last_fired_dma] <= 0;
                        write_fsm <= FSM_IDLE;
                    end
                end

                default: begin

                end
            endcase
        end
    end

endmodule