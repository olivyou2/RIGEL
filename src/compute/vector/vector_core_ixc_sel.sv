module vector_core_ixc_sel #(
    parameter ADDR_WIDTH = 32,
    parameter MASTER_N = 3,
    parameter SLAVE_N = 7,
    parameter SEL_WIDTH = (SLAVE_N > 1) ? $clog2(SLAVE_N + 1) : 1
) (
    input  logic [ADDR_WIDTH-1:0] addr_in[MASTER_N],
    output logic [ SEL_WIDTH-1:0] sel_out[MASTER_N]
);

    parameter DEV_SEL = 2;
    parameter ADDRESSING_RANGE = 18;

    always_comb begin
        for (int i = 0; i < MASTER_N; i++) begin
            logic [ADDRESSING_RANGE-1:0] addr_local;

            addr_local = addr_in[i][ADDRESSING_RANGE-1:0];
            // An unmapped address gets an invalid IXC selector instead of
            // accidentally falling through to DMA control.
            sel_out[i] = addr_in[i][ADDRESSING_RANGE+DEV_SEL-1: ADDRESSING_RANGE];
        end
    end
endmodule
