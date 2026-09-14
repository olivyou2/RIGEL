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
    input logic [ADDR_WIDTH-1: 0] read_addr_in[MASTER_N],
    input logic read_addr_valid[MASTER_N],
    output logic read_addr_ready[MASTER_N],

    output logic [ADDR_WIDTH-1: 0] ixc_addr_out[MASTER_N],
    input logic [SEL_WIDTH-1: 0] ixc_slave_sel[MASTER_N],

    output logic [DATA_WIDTH-1: 0] read_data_out[MASTER_N],
    output logic read_data_valid[MASTER_N],
    input logic read_data_ready[MASTER_N],

    input logic [ADDR_WIDTH-1: 0] write_addr_in[MASTER_N],
    input logic [DATA_WIDTH-1: 0] write_data_in[MASTER_N],
    input logic write_data_valid[MASTER_N],
    output logic write_data_ready[MASTER_N],

    output logic [ADDR_WIDTH-1: 0] ixc_write_addr_out[MASTER_N],
    input logic [SEL_WIDTH-1: 0] ixc_write_slave_sel[MASTER_N],

    // Slave Side
    output logic [ADDR_WIDTH-1: 0] slave_read_addr_out[SLAVE_N],
    output logic slave_read_addr_valid[SLAVE_N],
    input logic slave_read_addr_ready[SLAVE_N],

    input logic [DATA_WIDTH-1: 0] slave_read_data_in[SLAVE_N],
    input logic slave_read_data_valid[SLAVE_N],
    output logic slave_read_data_ready[SLAVE_N],

    output logic [ADDR_WIDTH-1 :0] slave_write_addr_out[SLAVE_N],
    output logic [DATA_WIDTH-1: 0] slave_write_data_out[SLAVE_N],
    output logic slave_write_data_valid[SLAVE_N],
    input logic slave_write_data_ready[SLAVE_N]
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
        .read_addr_in(read_addr_in), .read_addr_valid(read_addr_valid),
        .read_addr_ready(read_addr_ready), .read_sel(ixc_slave_sel),
        .read_data_out(read_data_out), .read_data_valid(read_data_valid),
        .read_data_ready(read_data_ready),
        .slave_read_addr_out(slave_read_addr_out),
        .slave_read_addr_valid(slave_read_addr_valid),
        .slave_read_addr_ready(slave_read_addr_ready),
        .slave_read_data_in(slave_read_data_in),
        .slave_read_data_valid(slave_read_data_valid),
        .slave_read_data_ready(slave_read_data_ready)
    );

    // External decoders are combinational. Capture selection with the payload.
    for (genvar m=0; m<MASTER_N; m++) begin: master_decode
        assign write_sel_reg[m] = write_sel_buffer[m][write_input_head[m]];
        assign ixc_addr_out[m] = read_addr_in[m];
        assign ixc_write_addr_out[m] = write_addr_in[m];
    end

    for (genvar s=0; s<SLAVE_N; s++) begin: write_output
        assign slave_write_addr_out[s] = write_addr_buffer[s][write_output_head[s]];
        assign slave_write_data_out[s] = write_data_buffer[s][write_output_head[s]];
    end

    // Control
    ixc_control #(
        .MASTER_N(MASTER_N), .SLAVE_N(SLAVE_N), .SEL_WIDTH(SEL_WIDTH)
    ) control (
        .clk(clk), .rst_n(rst_n),
        .write_data_valid(write_data_valid), .write_data_ready(write_data_ready),
        .write_sel(ixc_write_slave_sel), .write_sel_reg(write_sel_reg),
        .write_load(write_load), .write_pending(write_pending),
        .write_input_head(write_input_head), .write_input_tail(write_input_tail),
        .write_output_head(write_output_head), .write_output_tail(write_output_tail),
        .write_issue(write_issue), .write_grant(write_grant),
        .slave_write_data_valid(slave_write_data_valid),
        .slave_write_data_ready(slave_write_data_ready)
    );

    // Write datapath: master input and slave output queues.
    // Payload registers do not need reset; control valid bits qualify all data.
    always @(posedge clk) begin
        if (rst_n) begin
            for (int m=0; m<MASTER_N; m++) begin
                if (write_load[m]) begin
                    write_addr_reg[m][write_input_tail[m]] <= write_addr_in[m];
                    write_data_reg[m][write_input_tail[m]] <= write_data_in[m];
                    write_sel_buffer[m][write_input_tail[m]] <= ixc_write_slave_sel[m];
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
