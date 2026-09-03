module dma_src_addr#(
    parameter int ADDR_WIDTH=32
)(
    input logic clk,
    input logic rst_n,

    input logic addr_rst,
    input logic [ADDR_WIDTH-1: 0] addr_rst_src,
    input logic [ADDR_WIDTH-1: 0] addr_rst_step,

    input logic fire_in_valid,
    output logic fire_in_ready,

    output logic [ADDR_WIDTH-1: 0] addr_out,
    output logic addr_out_valid,
    input logic addr_out_ready
);

    logic [ADDR_WIDTH-1: 0] addr_src;
    logic [ADDR_WIDTH-1: 0] addr_next_src;
    logic [ADDR_WIDTH-1: 0] addr_step;

    logic [ADDR_WIDTH-1: 0] addr_skid;
    logic addr_skid_valid;

    assign addr_next_src = addr_src + addr_step;

    logic read_handshaked;
    logic write_handshaked;

    assign read_handshaked = (fire_in_valid && fire_in_ready);
    assign write_handshaked = (!addr_out_valid || (addr_out_valid && addr_out_ready)) ;

    assign fire_in_ready = !addr_skid_valid;

    task automatic write_addr
        (input logic [ADDR_WIDTH-1: 0] addr);
        addr_out_valid <= 1;

        addr_out <= addr;
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            addr_skid <= 0;
            addr_skid_valid <= 0;

            addr_src <= 0;
            addr_step <= 0;

            addr_out_valid <= 0;
        end else begin
            if (addr_rst) begin
                addr_src <= addr_rst_src;
                addr_step <= addr_rst_step;
            end else begin
                if (write_handshaked) begin
                    addr_out_valid <= 0;
                end

                if (write_handshaked) begin
                    // It can export data

                    if (addr_skid_valid) begin
                        addr_skid_valid <= 0;
                        write_addr(addr_skid);
                        addr_out <= addr_skid;
                    end else if (read_handshaked) begin
                        write_addr(addr_src);
                        addr_out <= addr_src;

                        addr_src <= addr_next_src;
                    end
                end else if (read_handshaked) begin
                    addr_skid_valid <= 1;
                    addr_skid <= addr_src;
                    addr_src <= addr_next_src;
                end
            end
        end
    end

endmodule
