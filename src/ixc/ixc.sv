module ixc#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,

    parameter MASTER_N = 2,
    parameter SLAVE_N = 2,
    parameter SEL_WIDTH = (SLAVE_N > 1) ? $clog2(SLAVE_N) : 1,
    parameter READ_FIFO_DEPTH = 4,
    parameter READ_OUTSTANDING = 8
)(
    input logic clk,
    input logic rst_n,

    // Master Side
    input logic [ADDR_WIDTH-1: 0] read_req_addr[MASTER_N],
    input logic read_req_valid[MASTER_N],
    output logic read_req_ready[MASTER_N],

    output logic [ADDR_WIDTH-1: 0] read_decode_addr[MASTER_N],
    input logic [SEL_WIDTH-1: 0] read_decode_sel[MASTER_N],

    output logic [DATA_WIDTH-1: 0] read_rsp_data[MASTER_N],
    output logic read_rsp_valid[MASTER_N],
    input logic read_rsp_ready[MASTER_N],

    input logic [ADDR_WIDTH-1: 0] write_req_addr[MASTER_N],
    input logic [DATA_WIDTH-1: 0] write_req_data[MASTER_N],
    input logic write_req_valid[MASTER_N],
    output logic write_req_ready[MASTER_N],

    output logic [ADDR_WIDTH-1: 0] write_decode_addr[MASTER_N],
    input logic [SEL_WIDTH-1: 0] write_decode_sel[MASTER_N],

    // Slave Side
    output logic [ADDR_WIDTH-1: 0] slave_read_req_addr[SLAVE_N],
    output logic slave_read_req_valid[SLAVE_N],
    input logic slave_read_req_ready[SLAVE_N],

    input logic [DATA_WIDTH-1: 0] slave_read_rsp_data[SLAVE_N],
    input logic slave_read_rsp_valid[SLAVE_N],
    output logic slave_read_rsp_ready[SLAVE_N],

    output logic [ADDR_WIDTH-1 :0] slave_write_req_addr[SLAVE_N],
    output logic [DATA_WIDTH-1: 0] slave_write_req_data[SLAVE_N],
    output logic slave_write_req_valid[SLAVE_N],
    input logic slave_write_req_ready[SLAVE_N]
);

    localparam MASTER_WIDTH = (MASTER_N > 1) ? $clog2(MASTER_N) : 1;
    logic write_load[MASTER_N], write_pending[MASTER_N];
    logic [SEL_WIDTH-1:0] write_sel_reg[MASTER_N];
    logic [ADDR_WIDTH-1:0] write_addr_reg[MASTER_N][2];
    logic [DATA_WIDTH-1:0] write_data_reg[MASTER_N][2];
    logic [SEL_WIDTH-1:0] write_sel_buffer[MASTER_N][2];
    logic write_input_head[MASTER_N], write_input_tail[MASTER_N];
    logic write_output_head[SLAVE_N], write_output_tail[SLAVE_N];
    logic [ADDR_WIDTH-1:0] write_addr_buffer[SLAVE_N][2];
    logic [DATA_WIDTH-1:0] write_data_buffer[SLAVE_N][2];
    logic write_issue[SLAVE_N];
    logic [MASTER_WIDTH-1:0] write_grant[SLAVE_N];

    initial begin
        if (MASTER_N < 1 || SLAVE_N < 1 || ADDR_WIDTH < 1 || DATA_WIDTH < 1)
            $fatal(1, "ixc parameters must be positive");
        if (SEL_WIDTH < ((SLAVE_N > 1) ? $clog2(SLAVE_N) : 1))
            $fatal(1, "SEL_WIDTH cannot represent every slave");
        if (READ_FIFO_DEPTH < 1)
            $fatal(1, "READ_FIFO_DEPTH must be positive");
    end

    ixc_read #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .MASTER_N(MASTER_N), .SLAVE_N(SLAVE_N), .SEL_WIDTH(SEL_WIDTH),
        .READ_FIFO_DEPTH(READ_FIFO_DEPTH), .READ_OUTSTANDING(READ_OUTSTANDING)
    ) read_path (
        .clk(clk), .rst_n(rst_n),
        .read_req_addr(read_req_addr), .read_req_valid(read_req_valid),
        .read_req_ready(read_req_ready), .read_sel(read_decode_sel),
        .read_rsp_data(read_rsp_data), .read_rsp_valid(read_rsp_valid),
        .read_rsp_ready(read_rsp_ready),
        .slave_read_req_addr(slave_read_req_addr),
        .slave_read_req_valid(slave_read_req_valid),
        .slave_read_req_ready(slave_read_req_ready),
        .slave_read_rsp_data(slave_read_rsp_data),
        .slave_read_rsp_valid(slave_read_rsp_valid),
        .slave_read_rsp_ready(slave_read_rsp_ready)
    );

    // External decoders are combinational. Capture selection with the payload.
    for (genvar m=0; m<MASTER_N; m++) begin: master_decode
        assign write_sel_reg[m] = write_sel_buffer[m][write_input_head[m]];
        assign read_decode_addr[m] = read_req_addr[m];
        assign write_decode_addr[m] = write_req_addr[m];
    end

    for (genvar s=0; s<SLAVE_N; s++) begin: write_output
        assign slave_write_req_addr[s] = write_addr_buffer[s][write_output_head[s]];
        assign slave_write_req_data[s] = write_data_buffer[s][write_output_head[s]];
    end

    // Control
    ixc_control #(
        .MASTER_N(MASTER_N), .SLAVE_N(SLAVE_N), .SEL_WIDTH(SEL_WIDTH)
    ) control (
        .clk(clk), .rst_n(rst_n),
        .write_req_valid(write_req_valid), .write_req_ready(write_req_ready),
        .write_sel(write_decode_sel), .write_sel_reg(write_sel_reg),
        .write_load(write_load), .write_pending(write_pending),
        .write_input_head(write_input_head), .write_input_tail(write_input_tail),
        .write_output_head(write_output_head), .write_output_tail(write_output_tail),
        .write_issue(write_issue), .write_grant(write_grant),
        .slave_write_req_valid(slave_write_req_valid),
        .slave_write_req_ready(slave_write_req_ready)
    );

    // Write datapath: master input and slave output queues.
    // Payload registers do not need reset; control valid bits qualify all data.
    always @(posedge clk) begin
        if (rst_n) begin
            for (int m=0; m<MASTER_N; m++) begin
                if (write_load[m]) begin
                    write_addr_reg[m][write_input_tail[m]] <= write_req_addr[m];
                    write_data_reg[m][write_input_tail[m]] <= write_req_data[m];
                    write_sel_buffer[m][write_input_tail[m]] <= write_decode_sel[m];
                end
            end
            for (int s=0; s<SLAVE_N; s++) begin
                if (write_issue[s]) begin
                    write_addr_buffer[s][write_output_tail[s]] <=
                        write_addr_reg[write_grant[s]][write_input_head[write_grant[s]]];
                    write_data_buffer[s][write_output_tail[s]] <=
                        write_data_reg[write_grant[s]][write_input_head[write_grant[s]]];
                end
            end
        end
    end
endmodule
