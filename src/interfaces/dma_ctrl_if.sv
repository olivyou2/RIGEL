// One DMA launch descriptor transferred with ready/valid.
// The source holds every descriptor field stable while valid && !ready.
interface dma_ctrl_if #(
    parameter int ADDR_WIDTH = 32
);
    logic valid;
    logic ready;

    logic [ADDR_WIDTH-1:0] length;
    logic [ADDR_WIDTH-1:0] step;
    logic [ADDR_WIDTH-1:0] addr_src;
    logic [ADDR_WIDTH-1:0] addr_dst;

    modport source(
        output valid, length, step, addr_src, addr_dst,
        input ready
    );

    modport sink(
        input valid, length, step, addr_src, addr_dst,
        output ready
    );
endinterface
