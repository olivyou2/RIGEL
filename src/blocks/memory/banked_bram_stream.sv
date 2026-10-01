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

    for (genvar p = 0; p < READ_PORTS; p++) begin : read_client
        assign rd_valid[p] = read_req[p].valid;
        assign rd_addr[p] = ADDR_WIDTH'(read_req[p].addr);
        assign rd_tag[p] = read_req[p].tag;
        assign rd_epoch[p] = read_req[p].epoch;
        assign read_req[p].ready = rd_ready[p];
        assign rsp_valid[p] = response_count[p] != 0;
        assign rsp_data[p] = response_data[p][0];
        assign rsp_addr[p] = response_addr[p][0];
        assign rsp_tag[p] = response_tag[p][0];
        assign rsp_epoch[p] = response_epoch[p][0];
        assign read_rsp[p].valid = rsp_valid[p];
        assign read_rsp[p].data = $bits(read_rsp[p].data)'(rsp_data[p]);
        assign read_rsp[p].addr = $bits(read_rsp[p].addr)'(rsp_addr[p]);
        assign read_rsp[p].tag = rsp_tag[p];
        assign read_rsp[p].epoch = rsp_epoch[p];
        assign rsp_ready[p] = read_rsp[p].ready;
    end
    for (genvar p = 0; p < WRITE_PORTS; p++) begin : write_client
        assign wr_valid[p] = write_req[p].valid;
        assign wr_addr[p] = ADDR_WIDTH'(write_req[p].addr);
        assign wr_data[p] = DATA_WIDTH'(write_req[p].data);
        assign write_req[p].ready = wr_ready[p];
    end

    logic [CLIENT_BITS-1:0] rr[BANKS];
    logic slot_valid[BANKS][2], slot_write[BANKS][2];
    logic [CLIENT_BITS-1:0] slot_client[BANKS][2];
    logic [ADDR_WIDTH-1:0] slot_addr[BANKS][2];
    logic [DATA_WIDTH-1:0] slot_data[BANKS][2], bank_read_data[BANKS][2];
    logic pending[BANKS][2];
    logic [READ_ID_BITS-1:0] pending_port[BANKS][2];
    logic [ADDR_WIDTH-1:0] pending_addr[BANKS][2];
    logic [TAG_WIDTH-1:0] pending_tag[BANKS][2];
    logic [EPOCH_WIDTH-1:0] pending_epoch[BANKS][2];

    // Round-robin over all logical clients. A same-word pair is permitted
    // only when both accesses are reads; writes serialize to avoid BRAM
    // cross-port collision semantics varying by device.
    always_comb begin
        rd_ready = '0;
        wr_ready = '0;
        for (int b = 0; b < BANKS; b++) begin
            for (int s = 0; s < 2; s++) begin
                slot_valid[b][s] = 1'b0;
                slot_write[b][s] = 1'b0;
                slot_client[b][s] = '0;
                slot_addr[b][s] = '0;
                slot_data[b][s] = '0;
                for (int offset = 0; offset < CLIENTS; offset++) begin
                    int candidate;
                    int write_index;
                    logic eligible;
                    logic is_write;
                    logic [ADDR_WIDTH-1:0] candidate_addr;
                    logic [DATA_WIDTH-1:0] candidate_data;
                    candidate = int'(rr[b]) + offset;
                    if (candidate >= CLIENTS) candidate -= CLIENTS;
                    is_write = candidate >= READ_PORTS;
                    write_index = candidate - READ_PORTS;
                    candidate_addr = '0;
                    candidate_data = '0;
                    eligible = 1'b0;
                    if (is_write) begin
                        candidate_addr = wr_addr[write_index];
                        candidate_data = wr_data[write_index];
                        eligible = wr_valid[write_index] &&
                                   bank_of(candidate_addr) == BANK_BITS'(b);
                    end else begin
                        candidate_addr = rd_addr[candidate];
                        eligible = rd_valid[candidate] &&
                                   bank_of(candidate_addr) == BANK_BITS'(b) &&
                                   (outstanding_count[candidate] <
                                    COUNT_BITS'(RESPONSE_DEPTH) ||
                                    (rsp_valid[candidate] && rsp_ready[candidate]));
                    end
                    if (s == 1 && slot_valid[b][0]) begin
                        if (slot_client[b][0] == CLIENT_BITS'(candidate))
                            eligible = 1'b0;
                        if (slot_addr[b][0][BYTE_BITS+:WORD_BITS] ==
                            candidate_addr[BYTE_BITS+:WORD_BITS] &&
                            (slot_write[b][0] || is_write))
                            eligible = 1'b0;
                    end
                    if (!slot_valid[b][s] && eligible && rst_n) begin
                        slot_valid[b][s] = 1'b1;
                        slot_write[b][s] = is_write;
                        slot_client[b][s] = CLIENT_BITS'(candidate);
                        slot_addr[b][s] = candidate_addr;
                        slot_data[b][s] = candidate_data;
                        if (is_write) wr_ready[write_index] = 1'b1;
                        else rd_ready[candidate] = 1'b1;
                    end
                end
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

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int p = 0; p < READ_PORTS; p++) begin
                response_count[p] <= '0;
                outstanding_count[p] <= '0;
                for (int q = 0; q < RESPONSE_DEPTH; q++) begin
                    response_data[p][q] <= '0;
                    response_addr[p][q] <= '0;
                    response_tag[p][q] <= '0;
                    response_epoch[p][q] <= '0;
                end
            end
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
            for (int p = 0; p < READ_PORTS; p++) begin
                logic consume;
                logic accept;
                int append_index;
                consume = rsp_valid[p] && rsp_ready[p];
                accept = rd_valid[p] && rd_ready[p];
                append_index = int'(response_count[p]) - int'(consume);
                if (consume) begin
                    for (int q = 0; q < RESPONSE_DEPTH-1; q++) begin
                        response_data[p][q] <= response_data[p][q+1];
                        response_addr[p][q] <= response_addr[p][q+1];
                        response_tag[p][q] <= response_tag[p][q+1];
                        response_epoch[p][q] <= response_epoch[p][q+1];
                    end
                end
                if (incoming_valid[p]) begin
                    response_data[p][append_index] <= incoming_data[p];
                    response_addr[p][append_index] <= incoming_addr[p];
                    response_tag[p][append_index] <= incoming_tag[p];
                    response_epoch[p][append_index] <= incoming_epoch[p];
                end
                case ({incoming_valid[p], consume})
                    2'b10: response_count[p] <= response_count[p] + 1'b1;
                    2'b01: response_count[p] <= response_count[p] - 1'b1;
                    default: ;
                endcase
                case ({accept, consume})
                    2'b10: outstanding_count[p] <= outstanding_count[p] + 1'b1;
                    2'b01: outstanding_count[p] <= outstanding_count[p] - 1'b1;
                    default: ;
                endcase
            end
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
