// Banked BRAM with an arbitrary number of logical read/write clients.
// Each bank is one physical true dual-port RAM. Either physical port can read
// or write, so a bank can accept 2R, 1R+1W, or 2W per cycle.
module banked_bram_stream #(
    parameter int BANKS = 4,
    parameter int READ_PORTS = 2,
    parameter int WRITE_PORTS = 2,
    parameter int DATA_WIDTH = 128,
    parameter int WORDS_PER_BANK = 1024,
    // Byte address. Bank bits are the MSBs of the local memory window;
    // optional higher system-address bits are ignored for memory selection.
    parameter int ADDR_WIDTH = $clog2(BANKS) + $clog2(WORDS_PER_BANK)
                             + $clog2(DATA_WIDTH/8),
    parameter int TAG_WIDTH = 4,
    parameter int EPOCH_WIDTH = 4,
    parameter int RESPONSE_DEPTH = 4
) (
    input logic clk,
    input logic rst_n,
    rv_if.sink read_req[READ_PORTS],
    rv_if.source read_rsp[READ_PORTS],
    rv_if.sink write_req[WRITE_PORTS]
);
    localparam int BANK_BITS = BANKS > 1 ? $clog2(BANKS) : 1;
    localparam int WORD_BITS = $clog2(WORDS_PER_BANK);
    localparam int BYTE_BITS = $clog2(DATA_WIDTH/8);
    localparam int LOCAL_ADDR_WIDTH = WORD_BITS + BYTE_BITS + (BANKS > 1 ? BANK_BITS : 0);
    localparam int CLIENTS = READ_PORTS + WRITE_PORTS;
    localparam int CLIENT_BITS = CLIENTS > 1 ? $clog2(CLIENTS) : 1;
    localparam int READ_ID_BITS = READ_PORTS > 1 ? $clog2(READ_PORTS) : 1;
    localparam int COUNT_BITS = $clog2(RESPONSE_DEPTH + 1);
    localparam int RESPONSE_INDEX_BITS = $clog2(RESPONSE_DEPTH);
    localparam int REQUEST_DEPTH = 2;

    initial begin
        if (BANKS < 1 || (BANKS & (BANKS-1)) != 0 ||
            READ_PORTS < 1 || WRITE_PORTS < 1 || RESPONSE_DEPTH < 2 ||
            WORDS_PER_BANK < 2 || (WORDS_PER_BANK & (WORDS_PER_BANK-1)) != 0 ||
            DATA_WIDTH < 8 || (DATA_WIDTH & (DATA_WIDTH-1)) != 0 ||
            ADDR_WIDTH < LOCAL_ADDR_WIDTH)
            $fatal(1, "banked_bram_stream requires power-of-two banks/words/width and sufficient address width");
    end

    function automatic logic [BANK_BITS-1:0] bank_of(
        input logic [ADDR_WIDTH-1:0] address
    );
        if (BANKS == 1) return '0;
        return address[LOCAL_ADDR_WIDTH-1-:BANK_BITS];
    endfunction

    logic [READ_PORTS-1:0] rd_valid, rd_ready, rsp_ready;
    logic [ADDR_WIDTH-1:0] rd_addr[READ_PORTS];
    logic [TAG_WIDTH-1:0] rd_tag[READ_PORTS];
    logic [EPOCH_WIDTH-1:0] rd_epoch[READ_PORTS];
    logic [WRITE_PORTS-1:0] wr_valid, wr_ready;
    logic [ADDR_WIDTH-1:0] wr_addr[WRITE_PORTS];
    logic [DATA_WIDTH-1:0] wr_data[WRITE_PORTS];

    // The external ready signals depend only on registered occupancy. Bank
    // arbitration and downstream backpressure cannot propagate through them.
    logic [1:0] rd_request_count[READ_PORTS], wr_request_count[WRITE_PORTS];
    logic rd_request_head[READ_PORTS], rd_request_tail[READ_PORTS];
    logic wr_request_head[WRITE_PORTS], wr_request_tail[WRITE_PORTS];
    logic [ADDR_WIDTH-1:0] rd_request_addr[READ_PORTS][REQUEST_DEPTH];
    logic [TAG_WIDTH-1:0] rd_request_tag[READ_PORTS][REQUEST_DEPTH];
    logic [EPOCH_WIDTH-1:0] rd_request_epoch[READ_PORTS][REQUEST_DEPTH];
    logic [ADDR_WIDTH-1:0] wr_request_addr[WRITE_PORTS][REQUEST_DEPTH];
    logic [DATA_WIDTH-1:0] wr_request_data[WRITE_PORTS][REQUEST_DEPTH];

    logic [READ_PORTS-1:0] rsp_valid;
    logic [DATA_WIDTH-1:0] rsp_data[READ_PORTS];
    logic [ADDR_WIDTH-1:0] rsp_addr[READ_PORTS];
    logic [TAG_WIDTH-1:0] rsp_tag[READ_PORTS];
    logic [EPOCH_WIDTH-1:0] rsp_epoch[READ_PORTS];
    logic [COUNT_BITS-1:0] response_count[READ_PORTS];
    logic [COUNT_BITS-1:0] outstanding_count[READ_PORTS];
    logic [DATA_WIDTH-1:0] response_data[READ_PORTS][RESPONSE_DEPTH];
    logic [ADDR_WIDTH-1:0] response_addr[READ_PORTS][RESPONSE_DEPTH];
    logic [TAG_WIDTH-1:0] response_tag[READ_PORTS][RESPONSE_DEPTH];
    logic [EPOCH_WIDTH-1:0] response_epoch[READ_PORTS][RESPONSE_DEPTH];
    logic [RESPONSE_INDEX_BITS-1:0] response_head[READ_PORTS];
    logic [RESPONSE_INDEX_BITS-1:0] response_tail[READ_PORTS];

    for (genvar p = 0; p < READ_PORTS; p++) begin : read_client
        assign rd_valid[p] = rd_request_count[p] != 0;
        assign rd_addr[p] = rd_request_addr[p][rd_request_head[p]];
        assign rd_tag[p] = rd_request_tag[p][rd_request_head[p]];
        assign rd_epoch[p] = rd_request_epoch[p][rd_request_head[p]];
        assign read_req[p].ready = rst_n && rd_request_count[p] < REQUEST_DEPTH;
        assign rsp_valid[p] = response_count[p] != 0;
        assign rsp_data[p] = response_data[p][response_head[p]];
        assign rsp_addr[p] = response_addr[p][response_head[p]];
        assign rsp_tag[p] = response_tag[p][response_head[p]];
        assign rsp_epoch[p] = response_epoch[p][response_head[p]];
        assign read_rsp[p].valid = rsp_valid[p];
        assign read_rsp[p].data = $bits(read_rsp[p].data)'(rsp_data[p]);
        assign read_rsp[p].addr = $bits(read_rsp[p].addr)'(rsp_addr[p]);
        assign read_rsp[p].tag = rsp_tag[p];
        assign read_rsp[p].epoch = rsp_epoch[p];
        assign rsp_ready[p] = read_rsp[p].ready;
    end
    for (genvar p = 0; p < WRITE_PORTS; p++) begin : write_client
        assign wr_valid[p] = wr_request_count[p] != 0;
        assign wr_addr[p] = wr_request_addr[p][wr_request_head[p]];
        assign wr_data[p] = wr_request_data[p][wr_request_head[p]];
        assign write_req[p].ready = rst_n && wr_request_count[p] < REQUEST_DEPTH;
    end

    logic [CLIENT_BITS-1:0] rr[BANKS];
    logic [CLIENTS-1:0] client_valid[BANKS];
    logic [CLIENTS-1:0] first_grant[BANKS], second_eligible[BANKS], second_grant[BANKS];
    logic [ADDR_WIDTH-1:0] client_addr[BANKS][CLIENTS];
    logic [DATA_WIDTH-1:0] client_data[BANKS][CLIENTS];
    logic client_write[CLIENTS];
    logic slot_valid[BANKS][2], slot_write[BANKS][2];
    logic [CLIENT_BITS-1:0] slot_client[BANKS][2];
    logic [ADDR_WIDTH-1:0] slot_addr[BANKS][2];
    logic [DATA_WIDTH-1:0] slot_data[BANKS][2], bank_read_data[BANKS][2];
    logic pending[BANKS][2];
    logic [READ_ID_BITS-1:0] pending_port[BANKS][2];
    logic [ADDR_WIDTH-1:0] pending_addr[BANKS][2];
    logic [TAG_WIDTH-1:0] pending_tag[BANKS][2];
    logic [EPOCH_WIDTH-1:0] pending_epoch[BANKS][2];

    // Decode each client once. In particular, the arbiter does not use a
    // variable client index to select a 128-bit payload on every priority step.
    for (genvar c = 0; c < CLIENTS; c++) begin : client_decode
        if (c < READ_PORTS) begin : read_port
            assign client_write[c] = 1'b0;
            for (genvar b = 0; b < BANKS; b++) begin : bank
                assign client_addr[b][c] = rd_addr[c];
                assign client_data[b][c] = '0;
                assign client_valid[b][c] = rd_valid[c] &&
                    bank_of(rd_addr[c]) == BANK_BITS'(b) &&
                    outstanding_count[c] < COUNT_BITS'(RESPONSE_DEPTH);
            end
        end else begin : write_port
            assign client_write[c] = 1'b1;
            for (genvar b = 0; b < BANKS; b++) begin : bank
                assign client_addr[b][c] = wr_addr[c-READ_PORTS];
                assign client_data[b][c] = wr_data[c-READ_PORTS];
                assign client_valid[b][c] = wr_valid[c-READ_PORTS] &&
                    bank_of(wr_addr[c-READ_PORTS]) == BANK_BITS'(b);
            end
        end
    end

    // Select both ports with one-hot grants. Every client tests its priority
    // against the other clients in parallel, avoiding a serial data mux at
    // each step of the round-robin search.
    always_comb begin
        rd_ready = '0;
        wr_ready = '0;
        for (int b = 0; b < BANKS; b++) begin
            for (int c = 0; c < CLIENTS; c++) begin
                first_grant[b][c] = client_valid[b][c] && rst_n;
                for (int k = 0; k < CLIENTS; k++) begin
                    if (k != c &&
                        ((CLIENT_BITS'(k) >= rr[b] && CLIENT_BITS'(c) < rr[b]) ||
                         ((CLIENT_BITS'(k) >= rr[b]) == (CLIENT_BITS'(c) >= rr[b]) && k < c)))
                        first_grant[b][c] &= !client_valid[b][k];
                end
            end
            for (int c = 0; c < CLIENTS; c++) begin
                second_eligible[b][c] = client_valid[b][c] && !first_grant[b][c] && rst_n;
                for (int k = 0; k < CLIENTS; k++) begin
                    if (k != c &&
                        client_addr[b][k][BYTE_BITS+:WORD_BITS] ==
                        client_addr[b][c][BYTE_BITS+:WORD_BITS] &&
                        (client_write[k] || client_write[c])) begin
                        second_eligible[b][c] &= !first_grant[b][k];
                    end
                end
            end
            for (int c = 0; c < CLIENTS; c++) begin
                second_grant[b][c] = second_eligible[b][c];
                for (int k = 0; k < CLIENTS; k++) begin
                    if (k != c &&
                        ((CLIENT_BITS'(k) >= rr[b] && CLIENT_BITS'(c) < rr[b]) ||
                         ((CLIENT_BITS'(k) >= rr[b]) == (CLIENT_BITS'(c) >= rr[b]) && k < c)))
                        second_grant[b][c] &= !second_eligible[b][k];
                end
            end
            for (int s = 0; s < 2; s++) begin
                slot_valid[b][s] = 1'b0;
                slot_write[b][s] = 1'b0;
                slot_client[b][s] = '0;
                slot_addr[b][s] = '0;
                slot_data[b][s] = '0;
                for (int c = 0; c < CLIENTS; c++) begin
                    if ((s == 0 && first_grant[b][c]) ||
                        (s == 1 && second_grant[b][c])) begin
                        slot_valid[b][s] = 1'b1;
                        slot_write[b][s] |= client_write[c];
                        slot_client[b][s] |= CLIENT_BITS'(c);
                        slot_addr[b][s] |= client_addr[b][c];
                        slot_data[b][s] |= client_data[b][c];
                    end
                end
            end
            for (int c = 0; c < CLIENTS; c++) begin
                if (c < READ_PORTS) rd_ready[c] |= first_grant[b][c] || second_grant[b][c];
                else wr_ready[c-READ_PORTS] |= first_grant[b][c] || second_grant[b][c];
            end
        end
    end

    for (genvar b = 0; b < BANKS; b++) begin : banks
        bram_dp #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .DATA_DEPTH(WORDS_PER_BANK)
        ) ram (
            .clk(clk),
            .addr_a(slot_addr[b][0]),
            .read_data_a(bank_read_data[b][0]),
            .write_data_a(slot_data[b][0]),
            .write_enable_a(slot_valid[b][0] && slot_write[b][0]),
            .addr_b(slot_addr[b][1]),
            .read_data_b(bank_read_data[b][1]),
            .write_data_b(slot_data[b][1]),
            .write_enable_b(slot_valid[b][1] && slot_write[b][1])
        );
    end

    logic [READ_PORTS-1:0] incoming_valid;
    logic [DATA_WIDTH-1:0] incoming_data[READ_PORTS];
    logic [ADDR_WIDTH-1:0] incoming_addr[READ_PORTS];
    logic [TAG_WIDTH-1:0] incoming_tag[READ_PORTS];
    logic [EPOCH_WIDTH-1:0] incoming_epoch[READ_PORTS];

    // bram_dp reads synchronously. One cycle after a grant, route each BRAM
    // output to its logical client's FIFO. Each client can issue one request
    // per cycle while it has response reservations available.
    always_comb begin
        incoming_valid = '0;
        for (int p = 0; p < READ_PORTS; p++) begin
            incoming_data[p] = '0;
            incoming_addr[p] = '0;
            incoming_tag[p] = '0;
            incoming_epoch[p] = '0;
        end
        for (int b = 0; b < BANKS; b++) begin
            for (int s = 0; s < 2; s++) begin
                if (pending[b][s]) begin
                    incoming_valid[pending_port[b][s]] = 1'b1;
                    incoming_data[pending_port[b][s]] = bank_read_data[b][s];
                    incoming_addr[pending_port[b][s]] = pending_addr[b][s];
                    incoming_tag[pending_port[b][s]] = pending_tag[b][s];
                    incoming_epoch[pending_port[b][s]] = pending_epoch[b][s];
                end
            end
        end
    end

    for (genvar p = 0; p < READ_PORTS; p++) begin : read_state
        wire consume = rsp_valid[p] && rsp_ready[p];
        wire grant = rd_valid[p] && rd_ready[p];
        wire enqueue = read_req[p].valid && read_req[p].ready;
        always_ff @(posedge clk) begin
            if (!rst_n) begin
                rd_request_count[p] <= '0;
                rd_request_head[p] <= 1'b0;
                rd_request_tail[p] <= 1'b0;
                response_count[p] <= '0;
                outstanding_count[p] <= '0;
                response_head[p] <= '0;
                response_tail[p] <= '0;
            end else begin
                if (enqueue) begin
                    rd_request_addr[p][rd_request_tail[p]] <= ADDR_WIDTH'(read_req[p].addr);
                    rd_request_tag[p][rd_request_tail[p]] <= read_req[p].tag;
                    rd_request_epoch[p][rd_request_tail[p]] <= read_req[p].epoch;
                    rd_request_tail[p] <= ~rd_request_tail[p];
                end
                if (grant) rd_request_head[p] <= ~rd_request_head[p];
                case ({enqueue, grant})
                    2'b10: rd_request_count[p] <= rd_request_count[p] + 1'b1;
                    2'b01: rd_request_count[p] <= rd_request_count[p] - 1'b1;
                    default: ;
                endcase
                if (consume) begin
                    response_head[p] <= response_head[p] == RESPONSE_INDEX_BITS'(RESPONSE_DEPTH-1)
                                      ? '0 : response_head[p] + 1'b1;
                end
                if (incoming_valid[p]) begin
                    response_data[p][response_tail[p]] <= incoming_data[p];
                    response_addr[p][response_tail[p]] <= incoming_addr[p];
                    response_tag[p][response_tail[p]] <= incoming_tag[p];
                    response_epoch[p][response_tail[p]] <= incoming_epoch[p];
                    response_tail[p] <= response_tail[p] == RESPONSE_INDEX_BITS'(RESPONSE_DEPTH-1)
                                      ? '0 : response_tail[p] + 1'b1;
                end
                case ({incoming_valid[p], consume})
                    2'b10: response_count[p] <= response_count[p] + 1'b1;
                    2'b01: response_count[p] <= response_count[p] - 1'b1;
                    default: ;
                endcase
                case ({grant, consume})
                    2'b10: outstanding_count[p] <= outstanding_count[p] + 1'b1;
                    2'b01: outstanding_count[p] <= outstanding_count[p] - 1'b1;
                    default: ;
                endcase
            end
        end
    end

    for (genvar p = 0; p < WRITE_PORTS; p++) begin : write_state
        wire enqueue = write_req[p].valid && write_req[p].ready;
        wire grant = wr_valid[p] && wr_ready[p];
        always_ff @(posedge clk) begin
            if (!rst_n) begin
                wr_request_count[p] <= '0;
                wr_request_head[p] <= 1'b0;
                wr_request_tail[p] <= 1'b0;
            end else begin
                if (enqueue) begin
                    wr_request_addr[p][wr_request_tail[p]] <= ADDR_WIDTH'(write_req[p].addr);
                    wr_request_data[p][wr_request_tail[p]] <= DATA_WIDTH'(write_req[p].data);
                    wr_request_tail[p] <= ~wr_request_tail[p];
                end
                if (grant) wr_request_head[p] <= ~wr_request_head[p];
                case ({enqueue, grant})
                    2'b10: wr_request_count[p] <= wr_request_count[p] + 1'b1;
                    2'b01: wr_request_count[p] <= wr_request_count[p] - 1'b1;
                    default: ;
                endcase
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int b = 0; b < BANKS; b++) begin
                rr[b] <= '0;
                for (int s = 0; s < 2; s++) begin
                    pending[b][s] <= 1'b0;
                    pending_port[b][s] <= '0;
                    pending_addr[b][s] <= '0;
                    pending_tag[b][s] <= '0;
                    pending_epoch[b][s] <= '0;
                end
            end
        end else begin
            for (int b = 0; b < BANKS; b++) begin
                if (slot_valid[b][0]) begin
                    rr[b] <= slot_client[b][0] == CLIENT_BITS'(CLIENTS-1)
                           ? '0 : slot_client[b][0] + 1'b1;
                end
                if (slot_valid[b][1]) begin
                    rr[b] <= slot_client[b][1] == CLIENT_BITS'(CLIENTS-1)
                           ? '0 : slot_client[b][1] + 1'b1;
                end
                for (int s = 0; s < 2; s++) begin
                    pending[b][s] <= slot_valid[b][s] && !slot_write[b][s];
                    if (slot_valid[b][s] && !slot_write[b][s]) begin
                        pending_port[b][s] <= READ_ID_BITS'(slot_client[b][s]);
                        pending_addr[b][s] <= slot_addr[b][s];
                        pending_tag[b][s] <= rd_tag[READ_ID_BITS'(slot_client[b][s])];
                        pending_epoch[b][s] <= rd_epoch[READ_ID_BITS'(slot_client[b][s])];
                    end
                end
            end
        end
    end
endmodule
