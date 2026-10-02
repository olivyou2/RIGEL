// Endpoint decoder: vector windows 0x000000..0x0fffff, system CSRs 0x100000.
module vector_tile #(parameter int WORDS_PER_BANK=512, WRITE_DEPTH=8)(
    input logic clk, rst_n, launch,
    input logic [31:0] launch_pc,
    rv_if.sink read_req, write_req,
    rv_if.source read_rsp, write_rsp,
    rv_if.source copy_read_req, copy_write_req,
    rv_if.sink copy_read_rsp, copy_write_rsp,
    output logic busy, done, fault
);
    rv_if #(.DATA_WIDTH(128)) core_rd(), core_wr(), core_rp(), core_wp();
    logic core_busy, core_done, core_fault, copy_busy, copy_done, copy_fault;
    logic csr_rvalid, csr_wvalid, local_fault, copy_start;
    logic [31:0] csr_ra, csr_wa, copy_src, copy_dst, copy_length;
    logic [127:0] csr_data, csr_wdata;
    logic [3:0] csr_rt, csr_re, csr_wt, csr_we;
    wire is_csr_read=read_req.addr[27:20]!=0;
    wire is_csr_write=write_req.addr[27:20]!=0;
    // Responses are selected by captured owner, not the live request address.
    localparam int CNT=$clog2(WRITE_DEPTH+1);
    logic [CNT-1:0] forwarded;
    logic read_local;
    logic rd_busy;
    assign busy=core_busy || copy_busy;
    assign done=!busy && (core_done || copy_done);
    assign fault=core_fault || copy_fault || local_fault;
    vector_tile_core #(.WORDS_PER_BANK(WORDS_PER_BANK),.WRITE_DEPTH(WRITE_DEPTH)) core(
        .clk(clk),.rst_n(rst_n),.launch(launch),.launch_pc(launch_pc),.read_req(core_rd),.write_req(core_wr),
        .read_rsp(core_rp),.write_rsp(core_wp),.busy(core_busy),.done(core_done),.fault(core_fault));
    tile_copy_engine copier(.clk(clk),.rst_n(rst_n),.start(copy_start),
        .source_addr(copy_src),.dest_addr(copy_dst),.length(copy_length),
        .busy(copy_busy),.done(copy_done),.fault(copy_fault),
        .read_req(copy_read_req),.write_req(copy_write_req),
        .read_rsp(copy_read_rsp),.write_rsp(copy_write_rsp));
    assign read_req.ready=rst_n && !rd_busy && (is_csr_read || core_rd.ready);
    assign write_req.ready=rst_n && !csr_wvalid && (is_csr_write ? forwarded==0 :
        (forwarded<CNT'(WRITE_DEPTH) && core_wr.ready));
    assign core_rd.valid=rst_n && !rd_busy && !is_csr_read && read_req.valid;
    assign core_wr.valid=rst_n && !csr_wvalid && forwarded<CNT'(WRITE_DEPTH) && !is_csr_write && write_req.valid;
    assign core_rd.addr=read_req.addr;
    assign core_rd.data=read_req.data;
    assign core_rd.tag=read_req.tag;
    assign core_rd.epoch=read_req.epoch;
    assign core_wr.addr=write_req.addr;
    assign core_wr.data=write_req.data;
    assign core_wr.tag=write_req.tag;
    assign core_wr.epoch=write_req.epoch;
    assign read_rsp.valid=rst_n && rd_busy && (read_local ? csr_rvalid : core_rp.valid);
    assign read_rsp.addr=read_local ? csr_ra : core_rp.addr;
    assign read_rsp.data=read_local ? csr_data : core_rp.data;
    assign read_rsp.tag=read_local ? csr_rt : core_rp.tag;
    assign read_rsp.epoch=read_local ? csr_re : core_rp.epoch;
    assign write_rsp.valid=rst_n && (csr_wvalid || (forwarded!=0 && core_wp.valid));
    assign write_rsp.addr=csr_wvalid ? csr_wa : core_wp.addr;
    assign write_rsp.data=csr_wvalid ? csr_wdata : core_wp.data;
    assign write_rsp.tag=csr_wvalid ? csr_wt : core_wp.tag;
    assign write_rsp.epoch=csr_wvalid ? csr_we : core_wp.epoch;
    assign core_rp.ready=rst_n && rd_busy && !read_local && read_rsp.ready;
    assign core_wp.ready=rst_n && !csr_wvalid && forwarded!=0 && write_rsp.ready;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            csr_rvalid<=0; csr_wvalid<=0; local_fault<=0; copy_start<=0;
            csr_ra<=0; csr_wa<=0; csr_data<=0; csr_wdata<=0;
            csr_rt<=0; csr_re<=0; csr_wt<=0; csr_we<=0;
            copy_src<=0; copy_dst<=0; copy_length<=0;
            read_local<=0; rd_busy<=0; forwarded<=0;
        end else begin
            copy_start<=0;
            case({core_wr.valid && core_wr.ready,core_wp.valid && core_wp.ready})
                2'b10:forwarded<=forwarded+1'b1;
                2'b01:forwarded<=forwarded-1'b1;
                default:;
            endcase
            if(read_rsp.valid && read_rsp.ready) begin rd_busy<=0; csr_rvalid<=0; end
            if(write_rsp.valid && write_rsp.ready && csr_wvalid) csr_wvalid<=0;
            if(read_req.valid && read_req.ready) begin
                rd_busy<=1; read_local<=is_csr_read;
                if(is_csr_read) begin
                    csr_ra<=read_req.addr; csr_rt<=read_req.tag; csr_re<=read_req.epoch; csr_rvalid<=1;
                    case(read_req.addr)
                        32'h100000:csr_data<={122'b0,copy_fault,copy_done,copy_busy,core_fault,core_done,core_busy};
                        32'h100010:csr_data<=128'(copy_src);
                        32'h100014:csr_data<=128'(copy_dst);
                        32'h100018:csr_data<=128'(copy_length);
                        default:begin csr_data<=0; local_fault<=1; end
                    endcase
                end
            end
            if(write_req.valid && write_req.ready) begin
                if(is_csr_write) begin
                    csr_wa<=write_req.addr; csr_wt<=write_req.tag; csr_we<=write_req.epoch;
                    csr_wvalid<=1; csr_wdata<=0;
                    if(copy_busy || copy_start) begin csr_wdata<=1; local_fault<=1; end
                    else case(write_req.addr)
                        32'h100010:copy_src<=write_req.data[31:0];
                        32'h100014:copy_dst<=write_req.data[31:0];
                        32'h100018:copy_length<=write_req.data[31:0];
                        32'h10001c:if(write_req.data==128'd1) copy_start<=1;
                            else begin csr_wdata<=1; local_fault<=1; end
                        default:begin csr_wdata<=1; local_fault<=1; end
                    endcase
                end
            end
        end
    end
endmodule
