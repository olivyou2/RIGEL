module compute_ixc_sel#(
    parameter ADDR_WIDTH = 32,
    parameter MASTER_N = 4,
    parameter SLAVE_N = 4
)(
    input logic [ADDR_WIDTH-1: 0] addr_in[MASTER_N],
    output logic [SLAVE_N-1: 0] sel_out[MASTER_N]
);

    // Addressing 의 상위 8bit 는 Mesh 내에서 X/Y 표시용 -> 따라서 하위 24bit 만 addressing 에 사용
    // AXI -> Mesh Converter 에서는 따로 addressing system 사용

    localparam logic [23:0] ADDR_DMA_CTRL_START = 24'h00_0000;
    localparam logic [23:0] ADDR_DMA_CTRL_END   = 24'h00_0FFF; // 4KB

    localparam logic [23:0] ADDR_BRAM_START     = 24'h00_1000;
    localparam logic [23:0] ADDR_BRAM_END       = 24'h00_8FFF; // 32KB

    localparam logic [23:0] ADDR_MATRIX_START   = 24'h01_0000;
    localparam logic [23:0] ADDR_MATRIX_END     = 24'h01_FFFF; // 64KB

    localparam logic [23:0] ADDR_VECTOR_START   = 24'h02_0000;
    localparam logic [23:0] ADDR_VECTOR_END     = 24'h02_FFFF; // 64KB

    initial begin
        if (SLAVE_N < 4) begin
            $fatal(1, "compute_ixc_sel requires SLAVE_N >= 4 for fixed range map");
        end
    end

    always_comb begin
        for (int i=0; i<MASTER_N; i++) begin
            logic [23:0] addr_local;

            sel_out[i] = '0;
            addr_local = addr_in[i][23:0];

            if ((addr_local >= ADDR_DMA_CTRL_START) && (addr_local <= ADDR_DMA_CTRL_END)) begin
                sel_out[i][0] = 1'b1;
            end else if ((addr_local >= ADDR_BRAM_START) && (addr_local <= ADDR_BRAM_END)) begin
                sel_out[i][1] = 1'b1;
            end else if ((addr_local >= ADDR_MATRIX_START) && (addr_local <= ADDR_MATRIX_END)) begin
                sel_out[i][2] = 1'b1;
            end else if ((addr_local >= ADDR_VECTOR_START) && (addr_local <= ADDR_VECTOR_END)) begin
                sel_out[i][3] = 1'b1;
            end
        end
    end

endmodule
