module compute#(
    parameter X_BITS=2,
    parameter Y_BITS=2,
    parameter OPCODE_BITS=4,
    parameter TAG_BITS=4,
    parameter ADDR_WIDTH=32,
    parameter DATA_WIDTH=64
)(
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1: 0] addr_in,
    input logic [DATA_WIDTH-1: 0] data_in,
    input logic [OPCODE_BITS-1: 0] opcode_in,
    input logic [TAG_BITS-1: 0] tag_in,
    input logic in_valid,
    output logic in_ready,

    output logic [ADDR_WIDTH-1: 0] addr_out,
    output logic [DATA_WIDTH-1: 0] data_out,
    output logic [OPCODE_BITS-1: 0] opcode_out,
    output logic [TAG_BITS-1: 0] tag_out,
    output logic out_valid,
    input logic out_ready
);
    localparam UNIT_ADDR_WIDTH = ADDR_WIDTH-X_BITS-Y_BITS;
    localparam DATASPACE_WIDTH = 16;
    localparam SEPERATOR_WIDTH = UNIT_ADDR_WIDTH - DATASPACE_WIDTH;

    logic [UNIT_ADDR_WIDTH-1: 0] addr_in_unitaddr;
    logic [SEPERATOR_WIDTH-1: 0] addr_in_seperator;
    logic [DATASPACE_WIDTH-1: 0] addr_in_dataspace;

    assign addr_in_unitaddr = addr_in[UNIT_ADDR_WIDTH-1: 0];
    assign addr_in_dataspace = addr_in_unitaddr[DATASPACE_WIDTH-1: 0];
    assign addr_in_seperator = addr_in_unitaddr[UNIT_ADDR_WIDTH-1: DATASPACE_WIDTH];

    // compute MMIO, 28bit = 0x0000_0000 ~ 0x0FFF_FFFF

    // 0x0000_0000 ~ 0000_7FFF  scratchpad A (W)
    // 0x0001_0000 ~ 0001_7FFF  scratchpad B (W)
    // 0X0002_0000 ~ 0002_7FFF  scratchpad C (R)

    // 0x0003_0000 ~ 0003_FFFF  DMA
    //  +00     src
    //  +08     dst
    //  +10     len
    //  +18     mode (0=burst, 1=scalar)
    //  +F8     fire

    // 0x0004_0000 ~ 0004_FFFF Registers
    //  +00     Compute status register
    //  +08     DMA status register
    //          [DECERR, RESERVATION]

    // registers
    logic decerr;

    // scratchpad A implement
    logic [ADDR_WIDTH-1: 0] spad_a_read_addr;
    logic [DATA_WIDTH-1: 0] spad_a_read_data;
    
    logic [ADDR_WIDTH-1: 0] spad_a_write_addr;
    logic [DATA_WIDTH-1: 0] spad_a_write_data;
    logic spad_a_write_enable;

    bram scratchpad_a(
        .clk(clk),
        .read_addr(spad_a_read_addr),
        .read_data(spad_a_read_data),
        .write_addr(spad_a_write_addr),
        .write_data(spad_a_write_data),
        .write_enable(spad_a_write_enable)
    );

    // scratchpad B implement
    logic [ADDR_WIDTH-1: 0] spad_b_read_addr;
    logic [DATA_WIDTH-1: 0] spad_b_read_data;
    
    logic [ADDR_WIDTH-1: 0] spad_b_write_addr;
    logic [DATA_WIDTH-1: 0] spad_b_write_data;
    logic spad_b_write_enable;

    bram scratchpad_b(
        .clk(clk),
        .read_addr(spad_b_read_addr),
        .read_data(spad_b_read_data),
        .write_addr(spad_b_write_addr),
        .write_data(spad_b_write_data),
        .write_enable(spad_b_write_enable)
    );

    // scratchpad C implement
    logic [ADDR_WIDTH-1: 0] spad_c_read_addr;
    logic [DATA_WIDTH-1: 0] spad_c_read_data;
    
    logic [ADDR_WIDTH-1: 0] spad_c_write_addr;
    logic [DATA_WIDTH-1: 0] spad_c_write_data;
    logic spad_c_write_enable;

    bram scratchpad_c(
        .clk(clk),
        .read_addr(spad_c_read_addr),
        .read_data(spad_c_read_data),
        .write_addr(spad_c_write_addr),
        .write_data(spad_c_write_data),
        .write_enable(spad_c_write_enable)
    );

    // DMA
    logic [ADDR_WIDTH-1: 0] dma_src_addr;
    logic [ADDR_WIDTH-1: 0] dma_dst_addr;
    logic [ADDR_WIDTH-1: 0] dma_len;

    // fire registers
    logic dma_fire;
    logic [ADDR_WIDTH-1: 0] dma_fire_src_addr;
    logic [ADDR_WIDTH-1: 0] dma_fire_dst_addr;
    logic [ADDR_WIDTH-1: 0] dma_fire_len;
    logic dma_dev; // 0=scratchpad C, 1=regs

    logic [ADDR_WIDTH-1: 0] dma_fire_counter;

    // dma data path
    logic [ADDR_WIDTH+DATA_WIDTH-1: 0] dma_arbitor_in;
    logic dma_arbitor_in_valid;
    logic dma_arbitor_in_ready;

    logic [1:0] dma_fsm;

    // output registers
    logic dma_decerr;

    // DMA Loader FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            dma_fsm <= 0;
            dma_fire_counter <= 0;
        end else begin case (dma_fsm)
                2'd0: begin
                    if (dma_fire) begin
                        dma_fire_counter <= 0;
                        dma_fsm <= 1;
                    end
                end

                2'd1: begin
                    if (dma_src_addr[UNIT_ADDR_WIDTH-1: DATASPACE_WIDTH] == 2) begin
                        // scratchpad C
                        dma_fire_src_addr <= dma_fire_src_addr[DATASPACE_WIDTH-1: 0];
                        dma_fsm <= 2;
                    end

                    else if (dma_src_addr[UNIT_ADDR_WIDTH-1: DATASPACE_WIDTH] == 4) begin
                        
                    end

                    else begin
                        dma_fsm <= 0;
                    end
                end
            endcase
        end
    end

    // Bus control FSM
    always @(posedge clk) begin
        // Reset Procedure
        if (!rst_n) begin
            in_ready <= 1;
            out_valid <= 0;

            decerr <= 0;
        end else begin
            spad_a_write_enable <= 0;
            spad_b_write_enable <= 0;

            decerr <= 0;
            
            if (in_valid && in_ready) begin
                case (addr_in_seperator) 
                    // Write at spad_a
                    12'h0: begin
                        spad_a_write_addr <= {16'b0, addr_in_dataspace};
                        spad_a_write_data <= data_in;

                        spad_a_write_enable <= 1;
                    end

                    // Write at spad_b
                    12'h1: begin
                        spad_b_write_addr <= {16'b0, addr_in_dataspace};
                        spad_b_write_data <= data_in;

                        spad_b_write_enable <= 1;
                    end

                    // Access at spad_c (Can't write)
                    12'h2: begin
                    end

                    // Write at DMA
                    12'h3: begin
                        dma_decerr <= 0;

                        if (addr_in_dataspace[15:0] == 16'h0) begin
                            dma_src_addr <= data_in[ADDR_WIDTH-1: 0];
                        end else if (addr_in_dataspace[15:0] == 16'h8) begin
                            dma_dst_addr <= data_in[ADDR_WIDTH-1: 0];
                        end else if (addr_in_dataspace[15:0] == 16'h10) begin
                            dma_len <= data_in[ADDR_WIDTH-1: 0];
                        end else if (addr_in_dataspace[15:0] == 16'hF8) begin
                            // DMA fire
                            $display("[COMPUTE_DMA] dma fired %8x -> %8x [LEN: %d]", dma_src_addr, dma_dst_addr, dma_len);
                            dma_fire_src_addr <= dma_src_addr;
                            dma_fire_dst_addr <= dma_dst_addr;
                            dma_fire_len <= dma_len;

                            dma_fire <= 1;
                        end else begin
                            dma_decerr <= 1;
                        end
                    end

                    default: begin
                        $display("COMPUTE decerr, %0x", addr_in_unitaddr);
                        decerr <= 1;
                    end
                endcase
            end
        end
    end

endmodule