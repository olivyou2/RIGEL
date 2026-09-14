// Slaves return one response per accepted AR, in acceptance order (no IDs).
// A master may pipeline reads to one destination; switching destinations waits
// for its earlier responses to drain, preserving master-visible ordering.
module ixc_read #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter MASTER_N = 2,
    parameter SLAVE_N = 2,
    parameter SEL_WIDTH = (SLAVE_N > 1) ? $clog2(SLAVE_N) : 1,
    parameter READ_FIFO_DEPTH = 4,
    parameter READ_OUTSTANDING = 8
)(
    input logic clk, rst_n,
    input logic [ADDR_WIDTH-1:0] read_addr_in[MASTER_N],
    input logic read_addr_valid[MASTER_N],
    output logic read_addr_ready[MASTER_N],
    input logic [SEL_WIDTH-1:0] read_sel[MASTER_N],
    output logic [DATA_WIDTH-1:0] read_data_out[MASTER_N],
    output logic read_data_valid[MASTER_N],
    input logic read_data_ready[MASTER_N],
    output logic [ADDR_WIDTH-1:0] slave_read_addr_out[SLAVE_N],
    output logic slave_read_addr_valid[SLAVE_N],
    input logic slave_read_addr_ready[SLAVE_N],
    input logic [DATA_WIDTH-1:0] slave_read_data_in[SLAVE_N],
    input logic slave_read_data_valid[SLAVE_N],
    output logic slave_read_data_ready[SLAVE_N]
);
    localparam MASTER_WIDTH = (MASTER_N > 1) ? $clog2(MASTER_N) : 1;
    localparam AR_PTR_WIDTH = (READ_FIFO_DEPTH > 1) ? $clog2(READ_FIFO_DEPTH) : 1;
    localparam AR_COUNT_WIDTH = $clog2(READ_FIFO_DEPTH + 1);
    localparam PTR_WIDTH = (READ_OUTSTANDING > 1) ? $clog2(READ_OUTSTANDING) : 1;
    localparam COUNT_WIDTH = $clog2(READ_OUTSTANDING + 1);

    logic [ADDR_WIDTH-1:0] request_addr[MASTER_N];
    logic [SEL_WIDTH-1:0] request_sel[MASTER_N], target[MASTER_N];
    logic request_valid[MASTER_N], request_take[MASTER_N];
    logic [COUNT_WIDTH-1:0] inflight[MASTER_N];
    logic issue[SLAVE_N], response_take[SLAVE_N];
    logic [MASTER_WIDTH-1:0] grant[SLAVE_N], owner[SLAVE_N];

    initial begin
        if (READ_FIFO_DEPTH < 1 || READ_OUTSTANDING < 1)
            $fatal(1, "IXC read queue depths must be positive");
    end

    function automatic logic [PTR_WIDTH-1:0] next_ptr(input logic [PTR_WIDTH-1:0] ptr);
        return (int'(ptr) == READ_OUTSTANDING-1) ? '0 : ptr + 1'b1;
    endfunction

    for (genvar m=0; m<MASTER_N; m++) begin: master_queue
        logic [ADDR_WIDTH-1:0] addr_mem[READ_FIFO_DEPTH];
        logic [SEL_WIDTH-1:0] sel_mem[READ_FIFO_DEPTH];
        logic [AR_PTR_WIDTH-1:0] ar_head, ar_tail;
        logic [AR_COUNT_WIDTH-1:0] ar_count;
        logic ar_push;

        logic [DATA_WIDTH-1:0] response_mem[READ_OUTSTANDING];
        logic [PTR_WIDTH-1:0] response_head, response_tail;
        logic [COUNT_WIDTH-1:0] response_count;
        logic response_push, response_pop;
        logic [DATA_WIDTH-1:0] response_data;

        assign read_addr_ready[m] = rst_n && (int'(ar_count) < READ_FIFO_DEPTH) &&
            (int'(read_sel[m]) < SLAVE_N);
        assign ar_push = read_addr_valid[m] && read_addr_ready[m];
        assign request_valid[m] = ar_count != 0;
        assign request_addr[m] = addr_mem[ar_head];
        assign request_sel[m] = sel_mem[ar_head];

        assign read_data_out[m] = response_mem[response_head];
        assign read_data_valid[m] = rst_n && (response_count != 0);
        assign response_pop = read_data_valid[m] && read_data_ready[m];

        always_comb begin
            request_take[m] = 0;
            response_push = 0;
            response_data = '0;
            for (int s=0; s<SLAVE_N; s++) begin
                if (issue[s] && int'(grant[s]) == m) request_take[m] = 1;
                if (response_take[s] && int'(owner[s]) == m) begin
                    response_push = 1;
                    response_data = slave_read_data_in[s];
                end
            end
        end

        always @(posedge clk) begin
            if (!rst_n) begin
                ar_head <= '0;
                ar_tail <= '0;
                ar_count <= '0;
                response_head <= '0;
                response_tail <= '0;
                response_count <= '0;
                inflight[m] <= '0;
                target[m] <= '0;
            end else begin
                if (ar_push) begin
                    addr_mem[ar_tail] <= read_addr_in[m];
                    sel_mem[ar_tail] <= read_sel[m];
                    ar_tail <= (int'(ar_tail) == READ_FIFO_DEPTH-1) ? '0 : ar_tail + 1'b1;
                end
                if (request_take[m]) begin
                    ar_head <= (int'(ar_head) == READ_FIFO_DEPTH-1) ? '0 : ar_head + 1'b1;
                    target[m] <= request_sel[m];
                end
                case ({ar_push, request_take[m]})
                    2'b10: ar_count <= ar_count + 1'b1;
                    2'b01: ar_count <= ar_count - 1'b1;
                    default: begin end
                endcase

                // Reserve response space BEFORE sending AR. Even a stalled
                // master cannot block delivery of another master's response.
                case ({request_take[m], response_pop})
                    2'b10: inflight[m] <= inflight[m] + 1'b1;
                    2'b01: inflight[m] <= inflight[m] - 1'b1;
                    default: begin end
                endcase
                if (response_push) begin
                    response_mem[response_tail] <= response_data;
                    response_tail <= next_ptr(response_tail);
                end
                if (response_pop) response_head <= next_ptr(response_head);
                case ({response_push, response_pop})
                    2'b10: response_count <= response_count + 1'b1;
                    2'b01: response_count <= response_count - 1'b1;
                    default: begin end
                endcase
            end
        end
    end

    for (genvar s=0; s<SLAVE_N; s++) begin: slave_queue
        // Keep the owner until R returns, but advance send_head on each AR.
        // Thus many addresses can be sent before the first response arrives.
        logic [ADDR_WIDTH-1:0] addr_mem[READ_OUTSTANDING];
        logic [MASTER_WIDTH-1:0] owner_mem[READ_OUTSTANDING];
        logic [PTR_WIDTH-1:0] tail, send_head, response_head;
        logic [COUNT_WIDTH-1:0] count, unsent_count;
        logic [MASTER_WIDTH-1:0] robin;
        logic addr_take;

        assign slave_read_addr_out[s] = addr_mem[send_head];
        assign slave_read_addr_valid[s] = rst_n && (unsent_count != 0);
        assign addr_take = slave_read_addr_valid[s] && slave_read_addr_ready[s];
        assign owner[s] = owner_mem[response_head];
        // Also accept a zero-latency response on the AR handshake itself.
        assign slave_read_data_ready[s] = rst_n && ((count > unsent_count) || addr_take);
        assign response_take[s] = slave_read_data_valid[s] && slave_read_data_ready[s];

        always_comb begin
            issue[s] = 0;
            grant[s] = '0;
            for (int offset=0; offset<MASTER_N; offset++) begin
                int m;
                m = int'(robin) + offset;
                if (m >= MASTER_N) m = m - MASTER_N;
                // Registered capacity only: no downstream ready -> AR grant path.
                if (rst_n && !issue[s] && int'(count) < READ_OUTSTANDING &&
                    request_valid[m] && int'(request_sel[m]) == s &&
                    int'(inflight[m]) < READ_OUTSTANDING &&
                    (inflight[m] == 0 || target[m] == request_sel[m])) begin
                    issue[s] = 1;
                    grant[s] = MASTER_WIDTH'(m);
                end
            end
        end

        always @(posedge clk) begin
            if (!rst_n) begin
                tail <= '0;
                send_head <= '0;
                response_head <= '0;
                count <= '0;
                unsent_count <= '0;
                robin <= '0;
            end else begin
                if (issue[s]) begin
                    addr_mem[tail] <= request_addr[grant[s]];
                    owner_mem[tail] <= grant[s];
                    tail <= next_ptr(tail);
                    robin <= (int'(grant[s]) == MASTER_N-1) ? '0 : grant[s] + 1'b1;
                end
                if (addr_take) send_head <= next_ptr(send_head);
                if (response_take[s]) response_head <= next_ptr(response_head);
                case ({issue[s], response_take[s]})
                    2'b10: count <= count + 1'b1;
                    2'b01: count <= count - 1'b1;
                    default: begin end
                endcase
                case ({issue[s], addr_take})
                    2'b10: unsent_count <= unsent_count + 1'b1;
                    2'b01: unsent_count <= unsent_count - 1'b1;
                    default: begin end
                endcase
            end
        end
    end
endmodule
