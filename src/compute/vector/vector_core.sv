module vector_core#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter LANE_WIDTH = 8,
    parameter LANE_SIZE = 16
)(
    input logic clk,
    input logic rst_n,

    rv_if.sink read_req,
    rv_if.source read_rsp,
    rv_if.sink write_req
);
    localparam MASTER_N = 3; // Interface, two DMA channels
    localparam SLAVE_N = 7; // DMA control, three BRAMs, ALU A/B/C
    localparam SEL_WIDTH = $clog2(SLAVE_N + 1);

    /**
           Interface     2ch DMA
               ↓            ↓
        ┌───────────────────────────────────────┐
        │      3x3 Interconnect                 │
        └───────────────────────────────────────┘
            ↓        ↓←←←←←←←←←←   ↓   ↓
            ↓        ↓         ↑   ↓   ↓
          BRAM A   BRAM B      A   L   U
    **/

    initial begin
        if (LANE_WIDTH * LANE_SIZE != DATA_WIDTH) begin
            $fatal(0, "LANE_WIDTH * LANE_SIZE missmatched with DATA_WIDTH (%0d * %0d != %0d)", LANE_WIDTH, LANE_SIZE, DATA_WIDTH);
        end
    end

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) ixc_read_req [MASTER_N]();

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) ixc_read_rsp [MASTER_N]();

     rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
      ) ixc_write_req [MASTER_N] ();

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) ixc_slave_read_req [SLAVE_N]();

    rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
     ) ixc_slave_read_rsp [SLAVE_N]();

     rv_if #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 64 */)
      ) ixc_slave_write_req [SLAVE_N] ();

    logic [ADDR_WIDTH-1: 0] ixc_addr_out[MASTER_N];
    logic [SEL_WIDTH-1: 0] ixc_slave_sel[MASTER_N];

    logic [ADDR_WIDTH-1: 0] ixc_write_addr_out[MASTER_N];
    logic [SEL_WIDTH-1: 0] ixc_write_slave_sel[MASTER_N];

    ixc #(
        .ADDR_WIDTH      (ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH      (DATA_WIDTH /* default 64 */),
        .MASTER_N        (MASTER_N /* default 2 */),
        .SLAVE_N         (SLAVE_N /* default 2 */),
        .SEL_WIDTH       (SEL_WIDTH),
        .READ_FIFO_DEPTH (4 /* default 4 */),
        .READ_OUTSTANDING(8 /* default 8 */)
     ) ixc (
        .clk                (clk),
        .rst_n              (rst_n),
        .read_req           (ixc_read_req),
        .ixc_addr_out       (ixc_addr_out),
        .ixc_slave_sel      (ixc_slave_sel),
        .read_rsp           (ixc_read_rsp),
        .write_req          (ixc_write_req),
        .ixc_write_addr_out (ixc_write_addr_out),
        .ixc_write_slave_sel(ixc_write_slave_sel),
        .slave_read_req     (ixc_slave_read_req),
        .slave_read_rsp     (ixc_slave_read_rsp),
        .slave_write_req    (ixc_slave_write_req)
    );

    vector_core_ixc_sel #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .MASTER_N  (MASTER_N /* default 4 */),
        .SLAVE_N   (SLAVE_N /* default 4 */),
        .SEL_WIDTH (SEL_WIDTH)
     ) vector_core_ixc_sel (
        .addr_in(ixc_addr_out),
        .sel_out(ixc_slave_sel)
    );

    vector_core_ixc_sel #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .MASTER_N  (MASTER_N /* default 4 */),
        .SLAVE_N   (SLAVE_N /* default 4 */),
        .SEL_WIDTH (SEL_WIDTH)
    ) vector_core_write_ixc_sel (
        .addr_in(ixc_write_addr_out),
        .sel_out(ixc_write_slave_sel)
    );


endmodule
