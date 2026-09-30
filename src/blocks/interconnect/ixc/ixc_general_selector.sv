module ixc_general_selector #(
    parameter ADDR_WIDTH = 32,
    parameter SEL_WIDTH = 3,
    parameter MASTER_N = 3
) (
    input  logic [ADDR_WIDTH-1:0] addr_in[MASTER_N],
    output logic [ SEL_WIDTH-1:0] sel_out[MASTER_N]
);

    parameter ADDRESSING_RANGE = ADDR_WIDTH - SEL_WIDTH;

    always_comb begin
        for (int i = 0; i < MASTER_N; i++) begin
            logic [ADDRESSING_RANGE-1:0] addr_local;

            addr_local = addr_in[i][ADDRESSING_RANGE-1:0];
            // An unmapped address gets an invalid IXC selector instead of
            // accidentally falling through to DMA control.
            sel_out[i] = addr_in[i][ADDRESSING_RANGE+SEL_WIDTH-1: ADDRESSING_RANGE];
        end
    end
endmodule