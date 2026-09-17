module bram_arbiter #(
    N = 4,
    DATA_WIDTH = 64,
    ADDR_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,

    // Interface side
    rv_if.sink read_req[N],

    rv_if.source read_rsp[N],

    // BRAM side
    rv_if.source slave_read_req,

    rv_if.sink slave_read_rsp
);
    logic [ADDR_WIDTH-1:0] addr_in[N];
    logic addr_valid[N];
    logic addr_ready[N];
    for (genvar ch_idx = 0; ch_idx < $size(addr_valid); ch_idx++) begin : map_read_req
        assign addr_in[ch_idx] = read_req[ch_idx].addr;
        assign addr_valid[ch_idx] = read_req[ch_idx].valid;
        assign read_req[ch_idx].ready = addr_ready[ch_idx];
    end
    logic [DATA_WIDTH-1:0] data_out[N];
    logic data_valid[N];
    logic data_ready[N];
    for (genvar ch_idx = 0; ch_idx < $size(data_valid); ch_idx++) begin : map_read_rsp
        assign read_rsp[ch_idx].data = data_out[ch_idx];
        assign read_rsp[ch_idx].valid = data_valid[ch_idx];
        assign data_ready[ch_idx] = read_rsp[ch_idx].ready;
        assign read_rsp[ch_idx].addr = '0;
    end
    assign slave_read_req.data = '0;

    /**

        Data path
        Interface Addr In -> Arbiter -> Addr Out
                                            BRAM -> Data out

    **/

    localparam N_WIDTH = $clog2(N);

    logic [ADDR_WIDTH-1:0] arb_addr_out;
    logic                  arb_addr_out_valid;
    logic                  arb_addr_out_ready;
    logic [   N_WIDTH-1:0] arb_addr_out_sel;

    logic                  sel_fifo_ready;
    logic [           1:0] req_out_valid;
    logic [           1:0] req_out_ready;
    logic [           1:0] req_sent;

    logic [   N_WIDTH-1:0] sel_out;
    logic                  sel_out_valid;
    logic                  sel_out_ready;

    logic [DATA_WIDTH-1:0] resp_join_data_in   [2];
    logic                  resp_join_valid_in  [2];
    logic                  resp_join_ready_in  [2];
    logic [DATA_WIDTH-1:0] resp_join_data_out  [2];
    logic                  resp_join_valid_out;
    logic                  resp_join_ready_out;

    logic [   N_WIDTH-1:0] resp_sel;
    logic [DATA_WIDTH-1:0] resp_data;
    logic                  target_ready;

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(ADDR_WIDTH)
    ) arbiter_in_ch[(N)] ();
    for (genvar ch_idx = 0; ch_idx < (N); ch_idx++) begin : connect_arbiter_in_ch
        assign arbiter_in_ch[ch_idx].data = addr_in[ch_idx];
        assign arbiter_in_ch[ch_idx].valid = addr_valid[ch_idx];
        assign addr_ready[ch_idx] = arbiter_in_ch[ch_idx].ready;
        assign arbiter_in_ch[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(ADDR_WIDTH)
    ) arbiter_out_ch ();
    assign arb_addr_out = arbiter_out_ch.data;
    assign arb_addr_out_valid = arbiter_out_ch.valid;
    assign arbiter_out_ch.ready = arb_addr_out_ready;
    arbiter_skid #(
        .DATA_WIDTH(ADDR_WIDTH  /* default 64 */),
        .N         (N  /* default 2 */)
    ) arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .data_out_sel(arb_addr_out_sel),
        .in_ch(arbiter_in_ch),
        .out_ch(arbiter_out_ch)
    );

    // Hold the request until both branches accept it, each exactly once.
    assign req_out_ready[0] = slave_read_req.ready;
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

    assign slave_read_req.addr  = arb_addr_out;
    assign slave_read_req.valid = req_out_valid[0];

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(N_WIDTH)
    ) sel_fifo_in_ch ();
    assign sel_fifo_in_ch.data = arb_addr_out_sel;
    assign sel_fifo_in_ch.valid = req_out_valid[1];
    assign sel_fifo_ready = sel_fifo_in_ch.ready;
    assign sel_fifo_in_ch.addr = '0;
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(N_WIDTH)
    ) sel_fifo_out_ch ();
    assign sel_out = sel_fifo_out_ch.data;
    assign sel_out_valid = sel_fifo_out_ch.valid;
    assign sel_fifo_out_ch.ready = sel_out_ready;
    fifo #(
        .DATA_WIDTH(N_WIDTH  /* default 64 */),
        .DATA_DEPTH(4)  // Cover read latency and keep accepting one selector per cycle.
    ) sel_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(sel_fifo_in_ch),
        .out_ch(sel_fifo_out_ch)
    );

    // Response phase joins selector and BRAM response data in lockstep.
    assign resp_join_data_in[0]  = {{(DATA_WIDTH - N_WIDTH) {1'b0}}, sel_out};
    assign resp_join_data_in[1]  = slave_read_rsp.data;
    assign resp_join_valid_in[0] = sel_out_valid;
    assign resp_join_valid_in[1] = slave_read_rsp.valid;

    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH(DATA_WIDTH)
    ) resp_join_in_ch[(2)] ();
    for (genvar ch_idx = 0; ch_idx < (2); ch_idx++) begin : connect_resp_join_in_ch
        assign resp_join_in_ch[ch_idx].data = resp_join_data_in[ch_idx];
        assign resp_join_in_ch[ch_idx].valid = resp_join_valid_in[ch_idx];
        assign resp_join_ready_in[ch_idx] = resp_join_in_ch[ch_idx].ready;
        assign resp_join_in_ch[ch_idx].addr = '0;
    end
    rv_if #(
        .ADDR_WIDTH(1),
        .DATA_WIDTH((DATA_WIDTH) * (2))
    ) resp_join_out_ch ();
    for (genvar lane = 0; lane < (2); lane++) begin : connect_resp_join_data_out
        assign resp_join_data_out[lane] = resp_join_out_ch.data[lane*(DATA_WIDTH)+:(DATA_WIDTH)];
    end
    assign resp_join_valid_out = resp_join_out_ch.valid;
    assign resp_join_out_ch.ready = resp_join_ready_out;
    handshake_join #(
        .DATA_WIDTH(DATA_WIDTH  /* default 64 */),
        .N         (2  /* default 4 */)
    ) resp_join (
        .clk(clk),
        .rst_n(rst_n),
        .in_ch(resp_join_in_ch),
        .out_ch(resp_join_out_ch)
    );

    assign sel_out_ready = resp_join_ready_in[0];
    assign slave_read_rsp.ready = resp_join_ready_in[1];

    assign resp_sel = resp_join_data_out[0][N_WIDTH-1:0];
    assign resp_data = resp_join_data_out[1];
    assign target_ready = !data_valid[resp_sel] || data_ready[resp_sel];
    assign resp_join_ready_out = target_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++) begin
                data_valid[i] <= 0;
            end
        end else begin
            for (int i = 0; i < N; i++) begin
                if (data_valid[i] && data_ready[i]) begin
                    data_valid[i] <= 0;
                end
            end

            if (resp_join_valid_out && resp_join_ready_out) begin
                data_out[resp_sel]   <= resp_data;
                data_valid[resp_sel] <= 1'b1;
            end
        end
    end

endmodule
