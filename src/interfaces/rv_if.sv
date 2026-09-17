// One independent ready/valid channel. Transfer occurs on valid && ready.
// Source owns payload/valid; sink owns ready. Hold payload while stalled.
// Data-only channels ignore addr; address-only channels ignore data.
// The source ties unused payload fields to zero.
interface rv_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64
);
    logic valid;
    logic ready;
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] data;

    modport source(output valid, addr, data, input ready);
    modport sink(input valid, addr, data, output ready);
endinterface
