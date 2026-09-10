module compute#(
    parameter X_BITS=2,
    parameter Y_BITS=2,
    parameter ADDR_WIDTH=32,
    parameter DATA_WIDTH=64
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] addr_in,
    input logic [DATA_WIDTH-1: 0] data_in,
    input logic in_valid,
    output logic in_ready,

    output logic [ADDR_WIDTH-1: 0] addr_out,
    output logic [DATA_WIDTH-1: 0] data_out,
    output logic out_valid,
    input logic out_ready
);
    localparam DATA_OUT_N = 4;

    /**
        N   description
        0   Main FSM Response
        1   DMA Response
        2   Reserved
        3   Reserved
    **/

    localparam POS_HEADER_SIZE = X_BITS + Y_BITS;
    localparam PAYLOAD_ADDR_SIZE = ADDR_WIDTH-POS_HEADER_SIZE;

    logic [PAYLOAD_ADDR_SIZE-1 :0] payload_addr;

    assign payload_addr = addr_in[PAYLOAD_ADDR_SIZE-1: 0];

    logic [ADDR_WIDTH-1: 0]     n_addr_out[DATA_OUT_N];
    logic [DATA_WIDTH-1: 0]     n_data_out[DATA_OUT_N];
    logic                       n_out_valid[DATA_OUT_N];
    logic                       n_out_ready[DATA_OUT_N];

    logic [ADDR_WIDTH+DATA_WIDTH-1: 0]
                                n_struct_out[DATA_OUT_N];

    always @(*) begin
        for (int i=0; i<DATA_OUT_N; i++) begin
            n_struct_out[i] = {n_data_out[i], n_addr_out[i]};
        end

    end

    arbiter #(
        .DATA_WIDTH(DATA_WIDTH + ADDR_WIDTH /* default 64 */),
        .N         (DATA_OUT_N /* default 2 */)
     ) arbiter (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (n_struct_out),
        .data_valid    (n_out_valid),
        .data_ready    (n_out_ready),
        .data_out      ({data_out, addr_out}),
        .data_out_valid(out_valid),
        .data_out_ready(out_ready)
    );

    // BRAM
    logic [ADDR_WIDTH-1: 0] read_addr_in;
    logic read_addr_in_valid;
    logic read_addr_in_ready;

    logic [DATA_WIDTH-1: 0] read_data_out;
    logic read_data_out_valid;
    logic read_data_out_ready;

    bram_stream #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) bram_stream (
        .clk                (clk),
        .rst_n              (rst_n),
        .read_addr_in       (read_addr_in),
        .read_addr_in_valid (read_addr_in_valid),
        .read_addr_in_ready (read_addr_in_ready),
        .read_data_out      (read_data_out),
        .read_data_out_valid(read_data_out_valid),
        .read_data_out_ready(read_data_out_ready),
        .write_addr_in      (write_addr_in),
        .write_data_in      (write_data_in),
        .write_data_valid   (write_data_valid),
        .write_data_ready   (write_data_ready)
    );

    // DMA
    logic fire_valid;
    logic fire_ready;

    logic [ADDR_WIDTH-1: 0] fire_length;
    logic [ADDR_WIDTH-1: 0] fire_step;
    logic [ADDR_WIDTH-1: 0] fire_addr_src;
    logic [ADDR_WIDTH-1: 0] fire_addr_dst;

    dma #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) dma (
        .clk               (clk),
        .rst_n             (rst_n),
        .addr_out          (read_addr_in),
        .addr_out_valid    (read_addr_in_valid),
        .addr_out_ready    (read_addr_in_ready),
        .data_in           (read_data_out),
        .data_in_valid     (read_data_out_valid),
        .data_in_ready     (read_data_out_ready),
        .dma_addr_out      (n_addr_out[1]),
        .dma_data_out      (n_data_out[1]),
        .dma_data_out_valid(n_out_valid[1]),
        .dma_data_out_ready(n_out_ready[1]),
        .fire_valid        (fire_valid),
        .fire_ready        (fire_ready),
        .fire_length       (fire_length),
        .fire_step         (fire_step),
        .fire_addr_src     (fire_addr_src),
        .fire_addr_dst     (fire_addr_dst)
    );

    // Control
    task automatic send(input logic [ADDR_WIDTH-1: 0] addr, input logic [DATA_WIDTH-1:0] data);
        n_data_out[0] <= data;
        n_addr_out[0] <= addr;
        n_out_valid[0] <= 1;
    endtask

    task automatic callback(input logic [PAYLOAD_ADDR_SIZE-1: 0] addr, input logic [DATA_WIDTH-1:0] data);
        logic [1:0] dst_x;
        logic [1:0] dst_y;

        dst_x = data_in[X_BITS-1: 0];
        dst_y = data_in[X_BITS+Y_BITS-1: X_BITS];

        send({dst_x, dst_y, addr}, data);
    endtask: callback

    logic [2:0] compute_main_fsm;

    localparam [PAYLOAD_ADDR_SIZE-1:0] REQ_GRANT = 'h0;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_LENGTH = 'h8;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_STEP = 'h10;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_ADDR_SRC = 'h18;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_ADDR_DST = 'h20;
    localparam [PAYLOAD_ADDR_SIZE-1:0] DMA_FIRE = 'h28;

    localparam [2:0] FSM_IDLE = 0;
    localparam [2:0] FSM_WAIT_OUT_READY = 1;
    localparam [2:0] FSM_WAIT_DMA_READY = 2;

    always @(posedge clk) begin
        if (!rst_n) begin
            n_out_valid[0] <= 0;

            compute_main_fsm <= 0;
            in_ready <= 1;
        end else begin
            case (compute_main_fsm) 
                FSM_IDLE: begin
                    if (in_ready && in_valid) begin
                        // $display("[core] data arrival=%0d, addr=%0d", data_in, payload_addr);
                        
                        case (payload_addr)
                            REQ_GRANT: begin
                                $display("[core] n_out_valid rise");
                                callback('h8, 'hAC7);

                                compute_main_fsm <= FSM_WAIT_OUT_READY; // Wait for Request done
                            end

                            DMA_LENGTH: begin
                                $display("[core_dma] dma_length set to %0d", data_in[31:0]);
                                fire_length <= data_in[31:0];
                            end

                            DMA_STEP: begin
                                $display("[core_dma] dma_step set to %0d", data_in[31:0]);
                                fire_step <= data_in[31:0];
                            end

                            DMA_ADDR_SRC: begin
                                $display("[core_dma] dma_addr_src set to %0h", data_in[31:0]);
                                fire_addr_src <= data_in[31:0];
                            end

                            DMA_ADDR_DST: begin
                                $display("[core_dma] dma_addr_dst set to %0h", data_in[31:0]);
                                fire_addr_dst <= data_in[31:0];
                            end

                            DMA_FIRE: begin
                                $display("[core_dma] trying to dma fire");
                                fire_valid <= 1;

                                compute_main_fsm <= FSM_WAIT_DMA_READY;
                            end

                            default: begin end
                        endcase
                    end
                end

                FSM_WAIT_OUT_READY: begin
                    if (n_out_valid[0] && n_out_ready[0]) begin
                        $display("[core] n_out_ready rise, handshaked");
                            
                        n_out_valid[0] <= 0;

                        compute_main_fsm <= FSM_IDLE;
                    end
                end

                FSM_WAIT_DMA_READY: begin
                    if (fire_valid && fire_ready) begin
                        $display("[core_dma] DMA launched");

                        fire_valid <= 0;
                        compute_main_fsm <= FSM_IDLE;
                    end
                end

                default: compute_main_fsm <= 0;
            endcase
        end
    end

endmodule