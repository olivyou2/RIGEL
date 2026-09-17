module dma_ixc_control #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,

    parameter DMA_N = 3
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink read_req,

    rv_if.source read_rsp,

    rv_if.sink write_req,

    dma_ctrl_if.source dma_ctrl[DMA_N]
);
    assign read_rsp.addr = '0;

    // Keep register storage in ordinary arrays because dynamic indexing into
    // interface arrays is not supported consistently across SV tools.
    logic [ADDR_WIDTH-1:0] fire_length  [DMA_N];
    logic [ADDR_WIDTH-1:0] fire_step    [DMA_N];
    logic [ADDR_WIDTH-1:0] fire_addr_src[DMA_N];
    logic [ADDR_WIDTH-1:0] fire_addr_dst[DMA_N];
    logic                  dma_fire     [DMA_N];
    logic                  dma_ready    [DMA_N];

    for (genvar i = 0; i < DMA_N; i++) begin : map_dma_ctrl
        assign dma_ctrl[i].length   = fire_length[i];
        assign dma_ctrl[i].step     = fire_step[i];
        assign dma_ctrl[i].addr_src = fire_addr_src[i];
        assign dma_ctrl[i].addr_dst = fire_addr_dst[i];
        assign dma_ctrl[i].valid    = dma_fire[i];
        assign dma_ready[i]         = dma_ctrl[i].ready;
    end

    logic [1:0] read_fsm;
    logic [1:0] write_fsm;

    logic [2:0] read_reg_idx;
    logic [2:0] read_dma_idx;

    assign read_reg_idx = read_req.addr[5:3];
    assign read_dma_idx = read_req.addr[8:6];

    logic [2:0] write_reg_idx;
    logic [2:0] write_dma_idx;

    assign write_reg_idx = write_req.addr[5:3];
    assign write_dma_idx = write_req.addr[8:6];

    localparam [1:0] FSM_IDLE = 0;
    localparam [1:0] FSM_READ_WAIT = 1;
    localparam [1:0] FSM_DMA_WAIT = 1;

    localparam REG_LENGTH = 3'd0;
    localparam REG_STEP = 3'd1;
    localparam REG_ADDR_SRC = 3'd2;
    localparam REG_ADDR_DST = 3'd3;
    localparam REG_FIRE = 3'd4;
    localparam REG_IDLE = 3'd5;

    assign read_req.ready = (read_fsm == FSM_IDLE);

    // Read FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            read_fsm <= 0;

            read_rsp.valid <= 0;
        end else begin
            case (read_fsm)
                FSM_IDLE: begin
                    if (read_req.ready && read_req.valid) begin
                        // 주소가 8B까지 확장될 여지가 있으므로
                        // ADDR_WIDTH[2:0] 는 0
                        // ADDR_WIDTH[5:3] 는 Reg Map
                        // ADDR_WIDTH[8:6] 는 DMA Index

                        read_fsm <= FSM_READ_WAIT;
                        read_rsp.valid <= 1;

                        case (read_reg_idx)
                            REG_LENGTH:   read_rsp.data <= fire_length[read_dma_idx];
                            REG_STEP:     read_rsp.data <= fire_step[read_dma_idx];
                            REG_ADDR_SRC: read_rsp.data <= fire_addr_src[read_dma_idx];
                            REG_ADDR_DST: read_rsp.data <= fire_addr_dst[read_dma_idx];
                            REG_IDLE:     read_rsp.data <= dma_ready[read_dma_idx];
                            default:      read_rsp.data <= 0;
                        endcase
                    end
                end

                FSM_READ_WAIT: begin
                    if (read_rsp.valid && read_rsp.ready) begin
                        read_rsp.valid <= 0;
                        read_fsm <= FSM_IDLE;
                    end
                end

                default: begin

                end
            endcase
        end
    end

    // Write FSM
    logic [$clog2(DMA_N):0] last_fired_dma;

    assign write_req.ready = write_fsm == FSM_IDLE;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < DMA_N; i++) begin
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
                    if (write_req.valid && write_req.ready) begin
                        case (write_reg_idx)
                            REG_LENGTH: begin
                                fire_length[write_dma_idx] <= write_req.data[ADDR_WIDTH-1:0];
                            end

                            REG_STEP: begin
                                fire_step[write_dma_idx] <= write_req.data[ADDR_WIDTH-1:0];
                            end

                            REG_ADDR_SRC: begin
                                fire_addr_src[write_dma_idx] <= write_req.data[ADDR_WIDTH-1:0];
                            end

                            REG_ADDR_DST: begin
                                fire_addr_dst[write_dma_idx] <= write_req.data[ADDR_WIDTH-1:0];
                            end

                            REG_FIRE: begin
                                dma_fire[write_dma_idx] <= 1;
                                last_fired_dma <= write_dma_idx;
                                write_fsm <= FSM_DMA_WAIT;
                            end

                            default: begin
                            end
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
