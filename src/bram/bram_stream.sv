module bram_stream #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter DATA_DEPTH = 1024  // 1024words = 1024 * 64 bits = 8KB
) (
    input logic clk,
    input logic rst_n,

    rv_if.sink read_req,

    rv_if.source read_rsp,

    rv_if.sink write_req
);
    assign read_rsp.addr = '0;

    logic [DATA_WIDTH-1:0] bram_skid_data[3];
    logic bram_skid_valid[3];

    logic [ADDR_WIDTH-1:0] read_addr;
    logic [DATA_WIDTH-1:0] read_data;

    logic [ADDR_WIDTH-1:0] write_addr;
    logic [DATA_WIDTH-1:0] write_data;
    logic write_enable;

    bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_DEPTH(DATA_DEPTH)
    ) bram_dut (
        .clk         (clk),
        .read_addr   (read_addr),
        .read_data   (read_data),
        .write_addr  (write_addr),
        .write_data  (write_data),
        .write_enable(write_enable)
    );

    logic read_pipeline[2];

    logic read_in_handshaked;

    logic read_out_acceptable;
    logic read_out_handshaked;

    assign read_in_handshaked  = read_req.valid && read_req.ready;

    assign read_out_handshaked = read_rsp.valid && read_rsp.ready;
    assign read_out_acceptable = (!read_rsp.valid) || read_out_handshaked;

    // Read Procedure
    always @(posedge clk) begin
        if (!rst_n) begin
            read_pipeline[0] <= 0;
            read_pipeline[1] <= 0;

            bram_skid_valid[0] <= 0;
            bram_skid_valid[1] <= 0;
            bram_skid_valid[2] <= 0;

            read_req.ready <= 1;
            read_rsp.valid <= 0;
        end else begin
            // Default pipeline
            read_pipeline[0] <= 0;

            if (read_in_handshaked) begin
                read_addr <= read_req.addr;

                // Set first pipeline stage
                read_pipeline[0] <= 1;
            end

            // Pipeline Propagate
            read_pipeline[1] <= read_pipeline[0];

            // Consume output
            if (read_out_handshaked) begin
                read_rsp.valid <= 0;
            end

            // Product output
            if (read_out_acceptable) begin
                // 1. if skid exists, then return skid first
                read_req.ready <= 1;

                if (bram_skid_valid[0]) begin
                    read_rsp.valid <= 1;
                    read_rsp.data <= bram_skid_data[0];

                    // shift skid data
                    bram_skid_valid[0] <= bram_skid_valid[1];
                    bram_skid_data[0] <= bram_skid_data[1];

                    bram_skid_valid[1] <= bram_skid_valid[2];
                    bram_skid_data[1] <= bram_skid_data[2];

                    bram_skid_valid[2] <= 0;

                    // << 이게 추가됨
                    if (read_pipeline[1]) begin
                        if (bram_skid_valid[2]) begin
                            bram_skid_data[2]  <= read_data;
                            bram_skid_valid[2] <= 1;
                        end else if (bram_skid_valid[1]) begin
                            bram_skid_data[1]  <= read_data;
                            bram_skid_valid[1] <= 1;
                        end else begin
                            bram_skid_data[0]  <= read_data;
                            bram_skid_valid[0] <= 1;
                        end
                    end
                end else if (read_pipeline[1]) begin
                    read_rsp.valid <= 1;
                    read_rsp.data  <= read_data;
                end

            end else begin
                read_req.ready <= 0;

                if (read_pipeline[1]) begin
                    if (!bram_skid_valid[0]) begin
                        bram_skid_valid[0] <= 1;
                        bram_skid_data[0]  <= read_data;
                    end else if (!bram_skid_valid[1]) begin
                        bram_skid_valid[1] <= 1;
                        bram_skid_data[1]  <= read_data;
                    end else if (!bram_skid_valid[2]) begin
                        bram_skid_valid[2] <= 1;
                        bram_skid_data[2]  <= read_data;
                    end else begin
                        $display("[BRAM_STREAM] fatal! skid out of context");
                    end
                end
            end
        end
    end

    // Write Procedure
    always @(posedge clk) begin
        if (!rst_n) begin
            write_req.ready <= 1;
        end else begin
            write_enable <= 0;

            if (write_req.ready && write_req.valid) begin
                write_addr   <= write_req.addr;
                write_data   <= write_req.data;
                write_enable <= 1;
            end
        end
    end

endmodule

/**
            0   1   2   3   4   5   6   7   8
    VALID   1   1   1   1   1   1   1   1   1
    READY   1   1   1   1   0   0   0   0   0
    O_VALID 0   0   0   1   1   1   1   1   1
    SKID    X   X   X   X   X   X   X   X   X

**/
