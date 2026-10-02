// ACK-aware DMA. ctrl.ready returns only after every destination ACK is consumed.
// Existing dma remains available for posted-write/local-only integrations.
module dma_with_write_rsp #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 128
)(
    input logic clk,
    input logic rst_n,
    rv_if.source read_req,
    rv_if.sink read_rsp,
    rv_if.source write_req,
    rv_if.sink write_rsp,
    dma_ctrl_if.sink ctrl
);
    logic addr_rst, addr_src_valid, addr_src_ready;
    logic [ADDR_WIDTH-1:0] addr_rst_src, addr_rst_dst, addr_rst_step;
    logic write_pending;
    logic [ADDR_WIDTH-1:0] pending_addr;
    logic [$bits(write_req.tag)-1:0] pending_tag;
    logic [$bits(write_req.epoch)-1:0] pending_epoch;
    rv_if #(.ADDR_WIDTH(1), .DATA_WIDTH(DATA_WIDTH),
            .TAG_WIDTH(read_rsp.TAG_WIDTH), .EPOCH_WIDTH(read_rsp.EPOCH_WIDTH)) buffered_data();
    rv_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
            .TAG_WIDTH(write_req.TAG_WIDTH), .EPOCH_WIDTH(write_req.EPOCH_WIDTH)) outgoing();

    dma_control #(.ADDR_WIDTH(ADDR_WIDTH)) control (
        .clk(clk), .rst_n(rst_n), .ctrl(ctrl), .addr_rst(addr_rst),
        .addr_rst_src(addr_rst_src), .addr_rst_dst(addr_rst_dst),
        .addr_rst_step(addr_rst_step), .addr_src_valid(addr_src_valid),
        .addr_src_ready(addr_src_ready),
        .dma_dataout_handshake(write_rsp.valid && write_rsp.ready)
    );
    dma_src_addr #(.ADDR_WIDTH(ADDR_WIDTH)) source_addr (
        .clk(clk), .rst_n(rst_n), .addr_rst(addr_rst),
        .addr_rst_src(addr_rst_src), .addr_rst_step(addr_rst_step),
        .fire_in_valid(addr_src_valid), .fire_in_ready(addr_src_ready), .read_req(read_req)
    );
    fifo #(.DATA_WIDTH(DATA_WIDTH), .TAG_WIDTH(read_rsp.TAG_WIDTH),
           .EPOCH_WIDTH(read_rsp.EPOCH_WIDTH)) data_fifo (
        .clk(clk), .rst_n(rst_n), .in_ch(read_rsp), .out_ch(buffered_data)
    );
    dma_dst_addr #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) destination_addr (
        .clk(clk), .rst_n(rst_n), .addr_rst(addr_rst),
        .addr_rst_dst(addr_rst_dst), .addr_rst_step(addr_rst_step),
        .in_ch(buffered_data), .out_ch(outgoing)
    );
    assign write_req.valid = rst_n && outgoing.valid && !write_pending;
    assign outgoing.ready = rst_n && write_req.ready && !write_pending;
    assign write_req.addr = outgoing.addr;
    assign write_req.data = outgoing.data;
    assign write_req.tag = outgoing.tag;
    assign write_req.epoch = outgoing.epoch;
    assign write_rsp.ready = rst_n && write_pending;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            write_pending <= 1'b0;
            pending_addr <= '0;
            pending_tag <= '0;
            pending_epoch <= '0;
        end
        else begin
            if (write_req.valid && write_req.ready) begin
                write_pending <= 1'b1;
                pending_addr <= write_req.addr;
                pending_tag <= write_req.tag;
                pending_epoch <= write_req.epoch;
            end
            if (write_rsp.valid && write_rsp.ready) write_pending <= 1'b0;
        end
    end
    // synthesis translate_off
    always @(posedge clk) if (rst_n && write_rsp.valid && write_rsp.ready) begin
        assert (write_rsp.addr == pending_addr && write_rsp.tag == pending_tag &&
                write_rsp.epoch == pending_epoch && write_rsp.data == '0)
            else $fatal(1, "dma_with_write_rsp: invalid write completion");
    end
    // synthesis translate_on
endmodule
