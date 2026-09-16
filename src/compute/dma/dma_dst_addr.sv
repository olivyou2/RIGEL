module dma_dst_addr#(
    parameter int DATA_WIDTH=64,
    parameter int ADDR_WIDTH=32
)(
    input logic clk,
    input logic rst_n,

    input logic addr_rst,
    input logic [ADDR_WIDTH-1: 0] addr_rst_dst,
    input logic [ADDR_WIDTH-1: 0] addr_rst_step,

    input logic [DATA_WIDTH-1: 0] data_in,
    input logic data_in_valid,
    output logic data_in_ready,

    output logic [DATA_WIDTH-1: 0] write_req_data,
    output logic [ADDR_WIDTH-1: 0] write_req_addr,
    output logic write_req_valid,
    input logic write_req_ready
);

    logic [ADDR_WIDTH-1: 0] addr_dst;
    logic [ADDR_WIDTH-1: 0] addr_next_dst;
    logic [ADDR_WIDTH-1: 0] addr_step;

    logic [DATA_WIDTH-1: 0] data_skid;
    logic data_skid_valid;

    assign addr_next_dst = addr_dst + addr_step;

    logic read_handshaked;
    logic write_handshaked;

    assign read_handshaked = (data_in_valid && data_in_ready);
    assign write_handshaked = (!write_req_valid || (write_req_valid && write_req_ready)) ;

    assign data_in_ready = !data_skid_valid;

    task automatic write_data
        (input logic [ADDR_WIDTH-1: 0] addr, input logic [DATA_WIDTH-1: 0] data);
        write_req_valid <= 1;

        write_req_data <= data;
        write_req_addr <= addr;
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            data_skid <= 0;
            data_skid_valid <= 0;

            addr_dst <= 0;
            addr_step <= 0;

            data_skid_valid <= 0;
            write_req_valid <= 0;
        end else begin
            if (addr_rst) begin
                addr_dst <= addr_rst_dst;
                addr_step <= addr_rst_step;
            end else begin
                if (write_handshaked) begin
                    write_req_valid <= 0;
                end

                if (write_handshaked) begin
                    // It can export data

                    if (data_skid_valid) begin
                        data_skid_valid <= 0;
                        write_data(addr_dst, data_skid);
                        addr_dst <= addr_next_dst;
                    end else if (read_handshaked) begin
                        write_data(addr_dst, data_in);
                        addr_dst <= addr_next_dst;
                    end
                end else if (read_handshaked) begin
                    data_skid_valid <= 1;
                    data_skid <= data_in;
                end
            end
        end
    end

endmodule
