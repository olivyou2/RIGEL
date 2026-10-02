// Flat-pin synthesis boundary. Four two-entry queues isolate host IO timing.
module rigel_mesh_top #(parameter int WORDS_PER_BANK=512, WRITE_DEPTH=8)(
    input logic clk, rst_n,
    input logic host_read_req_valid,
    output logic host_read_req_ready,
    input logic [31:0] host_read_req_addr,
    input logic [3:0] host_read_req_tag,
    input logic [3:0] host_read_req_epoch,
    input logic host_write_req_valid,
    output logic host_write_req_ready,
    input logic [31:0] host_write_req_addr,
    input logic [127:0] host_write_req_data,
    input logic [3:0] host_write_req_tag,
    input logic [3:0] host_write_req_epoch,
    output logic host_read_rsp_valid,
    input logic host_read_rsp_ready,
    output logic [31:0] host_read_rsp_addr,
    output logic [127:0] host_read_rsp_data,
    output logic [3:0] host_read_rsp_tag,
    output logic [3:0] host_read_rsp_epoch,
    output logic host_write_rsp_valid,
    input logic host_write_rsp_ready,
    output logic [31:0] host_write_rsp_addr,
    output logic [127:0] host_write_rsp_data,
    output logic [3:0] host_write_rsp_tag,
    output logic [3:0] host_write_rsp_epoch,
    output logic [15:0] busy, done, fault
);
    rv_if #(.DATA_WIDTH(128)) host_read_req(), host_read_req_buffered();
    assign host_read_req.valid=host_read_req_valid;
    assign host_read_req_ready=host_read_req.ready;
    assign host_read_req.addr=host_read_req_addr;
    assign host_read_req.data=0;
    assign host_read_req.tag=host_read_req_tag;
    assign host_read_req.epoch=host_read_req_epoch;
    rv_pipe_fifo #(.DATA_WIDTH(128)) host_read_req_boundary(.clk(clk),.rst_n(rst_n),.in_ch(host_read_req),.out_ch(host_read_req_buffered));
    rv_if #(.DATA_WIDTH(128)) host_write_req(), host_write_req_buffered();
    assign host_write_req.valid=host_write_req_valid;
    assign host_write_req_ready=host_write_req.ready;
    assign host_write_req.addr=host_write_req_addr;
    assign host_write_req.data=host_write_req_data;
    assign host_write_req.tag=host_write_req_tag;
    assign host_write_req.epoch=host_write_req_epoch;
    rv_pipe_fifo #(.DATA_WIDTH(128)) host_write_req_boundary(.clk(clk),.rst_n(rst_n),.in_ch(host_write_req),.out_ch(host_write_req_buffered));
    rv_if #(.DATA_WIDTH(128)) host_read_rsp(), host_read_rsp_buffered();
    assign host_read_rsp_valid=host_read_rsp.valid;
    assign host_read_rsp.ready=host_read_rsp_ready;
    assign host_read_rsp_addr=host_read_rsp.addr;
    assign host_read_rsp_data=host_read_rsp.data;
    assign host_read_rsp_tag=host_read_rsp.tag;
    assign host_read_rsp_epoch=host_read_rsp.epoch;
    rv_pipe_fifo #(.DATA_WIDTH(128)) host_read_rsp_boundary(.clk(clk),.rst_n(rst_n),.in_ch(host_read_rsp_buffered),.out_ch(host_read_rsp));
    rv_if #(.DATA_WIDTH(128)) host_write_rsp(), host_write_rsp_buffered();
    assign host_write_rsp_valid=host_write_rsp.valid;
    assign host_write_rsp.ready=host_write_rsp_ready;
    assign host_write_rsp_addr=host_write_rsp.addr;
    assign host_write_rsp_data=host_write_rsp.data;
    assign host_write_rsp_tag=host_write_rsp.tag;
    assign host_write_rsp_epoch=host_write_rsp.epoch;
    rv_pipe_fifo #(.DATA_WIDTH(128)) host_write_rsp_boundary(.clk(clk),.rst_n(rst_n),.in_ch(host_write_rsp_buffered),.out_ch(host_write_rsp));
    rigel_mesh_system #(.WORDS_PER_BANK(WORDS_PER_BANK),.WRITE_DEPTH(WRITE_DEPTH)) system_core(
        .clk(clk),.rst_n(rst_n),.scheduled_launch(16'b0),.scheduled_reserved(16'b0),.scheduled_pc(32'b0),.host_read_req(host_read_req_buffered),
        .host_write_req(host_write_req_buffered),.host_read_rsp(host_read_rsp_buffered),
        .host_write_rsp(host_write_rsp_buffered),.busy(busy),.done(done),.fault(fault));
endmodule
