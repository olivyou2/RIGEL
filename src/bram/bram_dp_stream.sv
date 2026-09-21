module bram_dp_stream #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int DATA_DEPTH = 1024
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink   read_req_a,
    rv_if.source read_rsp_a,
    rv_if.sink   write_req_a,

    rv_if.sink   read_req_b,
    rv_if.source read_rsp_b,
    rv_if.sink   write_req_b
);
    logic [ADDR_WIDTH-1:0] read_addr_a;
    logic [DATA_WIDTH-1:0] read_data_a;
    logic [ADDR_WIDTH-1:0] write_addr_a;
    logic [DATA_WIDTH-1:0] write_data_a;
    logic                  write_enable_a;

    logic [ADDR_WIDTH-1:0] read_addr_b;
    logic [DATA_WIDTH-1:0] read_data_b;
    logic [ADDR_WIDTH-1:0] write_addr_b;
    logic [DATA_WIDTH-1:0] write_data_b;
    logic                  write_enable_b;

    bram_dp #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_DEPTH(DATA_DEPTH)
    ) bram_dp_dut (
        .clk           (clk),
        .read_addr_a   (read_addr_a),
        .read_data_a   (read_data_a),
        .write_addr_a  (write_addr_a),
        .write_data_a  (write_data_a),
        .write_enable_a(write_enable_a),
        .read_addr_b   (read_addr_b),
        .read_data_b   (read_data_b),
        .write_addr_b  (write_addr_b),
        .write_data_b  (write_data_b),
        .write_enable_b(write_enable_b)
    );

    bram_dp_stream_port #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) port_a (
        .clk         (clk),
        .rst_n       (rst_n),
        .read_req    (read_req_a),
        .read_rsp    (read_rsp_a),
        .write_req   (write_req_a),
        .read_addr   (read_addr_a),
        .read_data   (read_data_a),
        .write_addr  (write_addr_a),
        .write_data  (write_data_a),
        .write_enable(write_enable_a)
    );

    bram_dp_stream_port #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) port_b (
        .clk         (clk),
        .rst_n       (rst_n),
        .read_req    (read_req_b),
        .read_rsp    (read_rsp_b),
        .write_req   (write_req_b),
        .read_addr   (read_addr_b),
        .read_data   (read_data_b),
        .write_addr  (write_addr_b),
        .write_data  (write_data_b),
        .write_enable(write_enable_b)
    );

endmodule

/* verilator lint_off DECLFILENAME */
module bram_dp_stream_port #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink   read_req,
    rv_if.source read_rsp,
    rv_if.sink   write_req,

    output logic [ADDR_WIDTH-1:0] read_addr,
    input  logic [DATA_WIDTH-1:0] read_data,
    output logic [ADDR_WIDTH-1:0] write_addr,
    output logic [DATA_WIDTH-1:0] write_data,
    output logic                  write_enable
);
    localparam int RESPONSE_DEPTH = 4;
    localparam int RESPONSE_COUNT_WIDTH = $clog2(RESPONSE_DEPTH + 1);
    localparam int RESPONSE_INDEX_WIDTH = $clog2(RESPONSE_DEPTH);
    localparam logic [RESPONSE_COUNT_WIDTH:0] RESPONSE_DEPTH_VALUE =
        RESPONSE_DEPTH[RESPONSE_COUNT_WIDTH:0];

    logic [DATA_WIDTH-1:0] response_data [0:RESPONSE_DEPTH-1];
    logic [RESPONSE_COUNT_WIDTH-1:0] response_count;
    logic [1:0] read_pipeline;
    logic       read_accepted;
    logic       response_consumed;
    logic [RESPONSE_COUNT_WIDTH:0] outstanding_reads;
    logic [RESPONSE_INDEX_WIDTH-1:0] append_index;

    integer i;

    assign read_rsp.addr = '0;

    always_comb begin
        outstanding_reads = {1'b0, response_count}
                          + {{RESPONSE_COUNT_WIDTH{1'b0}}, read_pipeline[0]}
                          + {{RESPONSE_COUNT_WIDTH{1'b0}}, read_pipeline[1]};

        read_rsp.valid   = (response_count != 0);
        read_rsp.data    = response_data[0];
        response_consumed = read_rsp.valid && read_rsp.ready;

        // A response consumed this cycle also releases one reservation.
        read_req.ready  = (outstanding_reads < RESPONSE_DEPTH_VALUE)
                       || response_consumed;
        write_req.ready = rst_n;

        read_accepted = read_req.valid && read_req.ready;
        if (response_consumed) begin
            append_index = response_count[RESPONSE_INDEX_WIDTH-1:0] - 1'b1;
        end else begin
            append_index = response_count[RESPONSE_INDEX_WIDTH-1:0];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_addr     <= '0;
            write_addr    <= '0;
            write_data    <= '0;
            write_enable  <= 1'b0;
            read_pipeline <= '0;
            response_count <= '0;
            for (i = 0; i < RESPONSE_DEPTH; i = i + 1) begin
                response_data[i] <= '0;
            end
        end else begin
            write_enable <= write_req.valid && write_req.ready;
            if (write_req.valid && write_req.ready) begin
                write_addr <= write_req.addr;
                write_data <= write_req.data;
            end

            read_pipeline[0] <= read_accepted;
            read_pipeline[1] <= read_pipeline[0];
            if (read_accepted) begin
                read_addr <= read_req.addr;
            end

            // Pop the oldest response. When a BRAM read completes in the same
            // cycle, append it after the responses that remain in the FIFO.
            if (response_consumed) begin
                for (i = 0; i < RESPONSE_DEPTH-1; i = i + 1) begin
                    response_data[i] <= response_data[i+1];
                end
            end

            if (read_pipeline[1]) begin
                response_data[append_index] <= read_data;
            end

            case ({read_pipeline[1], response_consumed})
                2'b10: response_count <= response_count + 1'b1;
                2'b01: response_count <= response_count - 1'b1;
                default: response_count <= response_count;
            endcase
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
