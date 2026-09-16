module bram_arbiter#(
    N=4,
    DATA_WIDTH=64,
    ADDR_WIDTH=32
)(
    input logic clk,
    input logic rst_n,

    // Interface side
    input logic [ADDR_WIDTH-1: 0] client_read_req_addr[N],
    input logic client_read_req_valid[N],
    output logic client_read_req_ready[N],

    output logic [DATA_WIDTH-1: 0] client_read_rsp_data[N],
    output logic client_read_rsp_valid[N],
    input logic client_read_rsp_ready[N],

    // BRAM side
    output logic [ADDR_WIDTH-1: 0] memory_read_req_addr,
    output logic memory_read_req_valid,
    input logic memory_read_req_ready,

    input logic [DATA_WIDTH-1: 0] memory_read_rsp_data,
    input logic memory_read_rsp_valid,
    output logic memory_read_rsp_ready
);

    /**

        Data path
        Interface Addr In -> Arbiter -> Addr Out
                                            BRAM -> Data out

    **/

    localparam N_WIDTH = $clog2(N);

    logic [ADDR_WIDTH-1:0] arb_addr_out;
    logic                  arb_addr_out_valid;
    logic                  arb_addr_out_ready;
    logic [N_WIDTH-1:0]    arb_addr_out_sel;

    logic sel_fifo_ready;
    logic [1:0] req_out_valid;
    logic [1:0] req_out_ready;
    logic [1:0] req_sent;

    logic [N_WIDTH-1:0] sel_out;
    logic sel_out_valid;
    logic sel_out_ready;

    logic [DATA_WIDTH-1:0] resp_join_data_in[2];
    logic resp_join_valid_in[2];
    logic resp_join_ready_in[2];
    logic [DATA_WIDTH-1:0] resp_join_data_out[2];
    logic resp_join_valid_out;
    logic resp_join_ready_out;

    logic [N_WIDTH-1:0] resp_sel;
    logic [DATA_WIDTH-1:0] resp_data;
    logic target_ready;

    arbiter_skid #(
        .DATA_WIDTH(ADDR_WIDTH /* default 64 */),
        .N         (N /* default 2 */)
     ) arbiter (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (client_read_req_addr),
        .data_in_valid (client_read_req_valid),
        .data_in_ready (client_read_req_ready),
        .data_out      (arb_addr_out),
        .data_out_valid(arb_addr_out_valid),
        .data_out_ready(arb_addr_out_ready),
        .data_out_sel  (arb_addr_out_sel)
    );

    // Hold the request until both branches accept it, each exactly once.
    assign req_out_ready[0] = memory_read_req_ready;
    assign req_out_ready[1] = sel_fifo_ready;

    assign req_out_valid = {2{arb_addr_out_valid}} & ~req_sent;
    assign arb_addr_out_ready = &(req_sent | req_out_ready);

    always @(posedge clk) begin
        if (!rst_n) begin
            req_sent <= '0;
        end else if (arb_addr_out_valid && arb_addr_out_ready) begin
            req_sent <= '0;
        end else begin
            req_sent <= req_sent | (req_out_valid & req_out_ready);
        end
    end

    assign memory_read_req_addr = arb_addr_out;
    assign memory_read_req_valid = req_out_valid[0];

    fifo #(
        .DATA_WIDTH(N_WIDTH /* default 64 */),
        .DATA_DEPTH(4) // Cover read latency and keep accepting one selector per cycle.
    ) sel_fifo (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (arb_addr_out_sel),
        .data_in_valid (req_out_valid[1]),
        .data_in_ready (sel_fifo_ready),
        .data_out      (sel_out),
        .data_out_valid(sel_out_valid),
        .data_out_ready(sel_out_ready)
    );

    // Response phase joins selector and BRAM response data in lockstep.
    assign resp_join_data_in[0] = {{(DATA_WIDTH-N_WIDTH){1'b0}}, sel_out};
    assign resp_join_data_in[1] = memory_read_rsp_data;
    assign resp_join_valid_in[0] = sel_out_valid;
    assign resp_join_valid_in[1] = memory_read_rsp_valid;

    handshake_join #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .N         (2 /* default 4 */)
    ) resp_join (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (resp_join_data_in),
        .data_in_valid (resp_join_valid_in),
        .data_in_ready (resp_join_ready_in),
        .data_out      (resp_join_data_out),
        .data_out_valid(resp_join_valid_out),
        .data_out_ready(resp_join_ready_out)
    );

    assign sel_out_ready = resp_join_ready_in[0];
    assign memory_read_rsp_ready = resp_join_ready_in[1];

    assign resp_sel = resp_join_data_out[0][N_WIDTH-1:0];
    assign resp_data = resp_join_data_out[1];
    assign target_ready = !client_read_rsp_valid[resp_sel] || client_read_rsp_ready[resp_sel];
    assign resp_join_ready_out = target_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i=0; i<N; i++) begin
                client_read_rsp_valid[i] <= 0;
            end
        end else begin
            for (int i=0; i<N; i++) begin
                if (client_read_rsp_valid[i] && client_read_rsp_ready[i]) begin
                    client_read_rsp_valid[i] <= 0;
                end
            end

            if (resp_join_valid_out && resp_join_ready_out) begin
                client_read_rsp_data[resp_sel] <= resp_data;
                client_read_rsp_valid[resp_sel] <= 1'b1;
            end
        end
    end

endmodule
