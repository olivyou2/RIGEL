module dma_dst_addr #(
    parameter int DATA_WIDTH = 64,
    parameter int ADDR_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,

    input logic addr_rst,
    input logic [ADDR_WIDTH-1:0] addr_rst_dst,
    input logic [ADDR_WIDTH-1:0] addr_rst_step,

    rv_if.sink in_ch,

    rv_if.source out_ch
);

    logic [ADDR_WIDTH-1:0] addr_dst;
    logic [ADDR_WIDTH-1:0] addr_next_dst;
    logic [ADDR_WIDTH-1:0] addr_step;

    logic [DATA_WIDTH-1:0] data_skid;
    logic data_skid_valid;

    assign addr_next_dst = addr_dst + addr_step;

    logic read_handshaked;
    logic write_handshaked;

    assign read_handshaked = (in_ch.valid && in_ch.ready);
    assign write_handshaked = (!out_ch.valid || (out_ch.valid && out_ch.ready));

    assign in_ch.ready = !data_skid_valid;

    task automatic write_data(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data);
        out_ch.valid <= 1;

        out_ch.data  <= data;
        out_ch.addr  <= addr;
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            data_skid <= 0;
            data_skid_valid <= 0;

            addr_dst <= 0;
            addr_step <= 0;

            data_skid_valid <= 0;
            out_ch.valid <= 0;
        end else begin
            if (addr_rst) begin
                addr_dst  <= addr_rst_dst;
                addr_step <= addr_rst_step;
            end else begin
                if (write_handshaked) begin
                    out_ch.valid <= 0;
                end

                if (write_handshaked) begin
                    // It can export data

                    if (data_skid_valid) begin
                        data_skid_valid <= 0;
                        write_data(addr_dst, data_skid);
                        addr_dst <= addr_next_dst;
                    end else if (read_handshaked) begin
                        write_data(addr_dst, in_ch.data);
                        addr_dst <= addr_next_dst;
                    end
                end else if (read_handshaked) begin
                    data_skid_valid <= 1;
                    data_skid <= in_ch.data;
                end
            end
        end
    end

endmodule
