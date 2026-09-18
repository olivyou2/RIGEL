module vector_core_ixc_sel #(
    parameter ADDR_WIDTH = 32,
    parameter MASTER_N = 3,
    parameter SLAVE_N = 7,
    parameter SEL_WIDTH = (SLAVE_N > 1) ? $clog2(SLAVE_N + 1) : 1
) (
    input  logic [ADDR_WIDTH-1:0] addr_in[MASTER_N],
    output logic [ SEL_WIDTH-1:0] sel_out[MASTER_N]
);
    localparam int ADDRESSING_RANGE = 20;
    localparam int REQUIRED_SLAVES = 7;

    // The parent compute interconnect assigns a 1 MiB window to the vector
    // engine. Decode its lower 20 address bits into seven 64 KiB local windows.
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_DMA_CTRL_START = 20'h0_0000;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_DMA_CTRL_END   = 20'h0_FFFF;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_BRAM_1_START   = 20'h1_0000;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_BRAM_1_END     = 20'h1_FFFF;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_BRAM_2_START   = 20'h2_0000;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_BRAM_2_END     = 20'h2_FFFF;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_BRAM_3_START   = 20'h3_0000;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_BRAM_3_END     = 20'h3_FFFF;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_ALU_A_START    = 20'h4_0000;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_ALU_A_END      = 20'h4_FFFF;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_ALU_B_START    = 20'h5_0000;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_ALU_B_END      = 20'h5_FFFF;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_ALU_C_START    = 20'h6_0000;
    localparam logic [ADDRESSING_RANGE-1:0] ADDR_ALU_C_END      = 20'h6_FFFF;

    localparam int SEL_DMA_CTRL = 0;
    localparam int SEL_BRAM_1   = 1;
    localparam int SEL_BRAM_2   = 2;
    localparam int SEL_BRAM_3   = 3;
    localparam int SEL_ALU_A    = 4;
    localparam int SEL_ALU_B    = 5;
    localparam int SEL_ALU_C    = 6;

    initial begin
        if (ADDR_WIDTH < ADDRESSING_RANGE)
            $fatal(1, "vector_core_ixc_sel requires ADDR_WIDTH >= %0d", ADDRESSING_RANGE);
        if (SLAVE_N < REQUIRED_SLAVES)
            $fatal(1, "vector_core_ixc_sel requires SLAVE_N >= %0d", REQUIRED_SLAVES);
        if ((1 << SEL_WIDTH) <= SLAVE_N)
            $fatal(1, "SEL_WIDTH must also represent an invalid slave index");
    end

    always_comb begin
        for (int i = 0; i < MASTER_N; i++) begin
            logic [ADDRESSING_RANGE-1:0] addr_local;

            addr_local = addr_in[i][ADDRESSING_RANGE-1:0];
            // An unmapped address gets an invalid IXC selector instead of
            // accidentally falling through to DMA control.
            sel_out[i] = SEL_WIDTH'(SLAVE_N);

            if (addr_local >= ADDR_DMA_CTRL_START && addr_local <= ADDR_DMA_CTRL_END)
                sel_out[i] = SEL_WIDTH'(SEL_DMA_CTRL);
            else if (addr_local >= ADDR_BRAM_1_START && addr_local <= ADDR_BRAM_1_END)
                sel_out[i] = SEL_WIDTH'(SEL_BRAM_1);
            else if (addr_local >= ADDR_BRAM_2_START && addr_local <= ADDR_BRAM_2_END)
                sel_out[i] = SEL_WIDTH'(SEL_BRAM_2);
            else if (addr_local >= ADDR_BRAM_3_START && addr_local <= ADDR_BRAM_3_END)
                sel_out[i] = SEL_WIDTH'(SEL_BRAM_3);
            else if (addr_local >= ADDR_ALU_A_START && addr_local <= ADDR_ALU_A_END)
                sel_out[i] = SEL_WIDTH'(SEL_ALU_A);
            else if (addr_local >= ADDR_ALU_B_START && addr_local <= ADDR_ALU_B_END)
                sel_out[i] = SEL_WIDTH'(SEL_ALU_B);
            else if (addr_local >= ADDR_ALU_C_START && addr_local <= ADDR_ALU_C_END)
                sel_out[i] = SEL_WIDTH'(SEL_ALU_C);
        end
    end
endmodule
