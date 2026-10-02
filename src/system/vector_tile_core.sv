// Hand-maintained tile integration of the existing vector_system datapath.
// Host requests are captured, decoded, issued, then answered in separate stages.
module vector_tile_core #(parameter int WORDS_PER_BANK=512, WRITE_DEPTH=8)(
    input logic clk, rst_n, launch,
    input logic [31:0] launch_pc,
    rv_if.sink read_req, write_req,
    rv_if.source read_rsp, write_rsp,
    output logic busy, done, fault
);
    rv_if #(.DATA_WIDTH(128)) ar[3](), ap[3](), aw[1](), ab[1]();
    rv_if #(.DATA_WIDTH(128)) cr[2](), cp[2](), cw[2](), cb[2]();
    rv_if #(.DATA_WIDTH(32)) ir[2](), ip[2](), iw[1](), ib[1]();
    rv_if #(.DATA_WIDTH(128)) operands[4]();
    rv_if #(.DATA_WIDTH(512)) joined();
    rv_if #(.DATA_WIDTH(272)) raw();
    rv_if #(.DATA_WIDTH(128)) results(), sch_wr();
    dma_ctrl_if controls[3]();
    logic kick_pending;
    logic [31:0] kick_pc;
    logic running, sch_fault, alu_done, host_fault, acc_unflushed;
    logic [2:0] dma_idle;
    logic [31:0] flushes;
    typedef enum logic [1:0] {IDLE, ISSUE, WAIT_RSP, REPLY} state_t;
    state_t rs;
    logic [31:0] ra, wa;
    logic [127:0] wd, rdata;
    logic [3:0] rt, re, wt, we;
    logic [1:0] rd_sel, wr_sel;
    logic rd_bad, wr_bad;
    localparam int VECTOR_BYTES=2*WORDS_PER_BANK*16;
    localparam int INSTR_BYTES=2*WORDS_PER_BANK*4;
    initial if(WORDS_PER_BANK<2 || (WORDS_PER_BANK & (WORDS_PER_BANK-1))!=0 || VECTOR_BYTES>262144)
        $fatal(1,"vector_tile_core memory depth must fit each 256 KiB window");
    function automatic logic valid_read(input logic [31:0] a);
        if(a[31:20]!=0) return 0;
        case(a[19:18])
            2'd0,2'd3:return {1'b0,a[17:0]}<19'(VECTOR_BYTES) && a[3:0]==0;
            2'd1:return {1'b0,a[17:0]}<19'(INSTR_BYTES) && a[1:0]==0;
            2'd2:return a[17:0]==0;
            default:return 0;
        endcase
    endfunction
    function automatic logic valid_write(input logic [31:0] a);
        if(a[31:20]!=0) return 0;
        if(a[19:18]!=2'd2) return valid_read(a);
        return (a[17:0]<=18'h44 && a[1:0]==0) || a[17:0]==18'h80;
    endfunction
    assign read_req.ready=rst_n && rs==IDLE;
    localparam int WPTR=WRITE_DEPTH>1 ? $clog2(WRITE_DEPTH) : 1;
    localparam int WCNT=$clog2(WRITE_DEPTH+1);
    typedef struct packed {
        logic [31:0] addr;
        logic [127:0] data;
        logic [3:0] tag, epoch;
        logic [1:0] device;
        logic bad;
    } host_write_t;
    host_write_t host_writes[WRITE_DEPTH];
    logic [127:0] host_status[WRITE_DEPTH];
    logic [WRITE_DEPTH-1:0] host_complete, host_live, host_sent;
    logic [WPTR-1:0] w_tail, w_issue, w_head;
    logic [WCNT-1:0] w_count, w_queued;
    logic w_issue_fire;
    function automatic logic [WPTR-1:0] next_write(input logic [WPTR-1:0] p);
        return p==WPTR'(WRITE_DEPTH-1) ? '0 : p+1'b1;
    endfunction
    wire w_accept=write_req.valid && write_req.ready;
    wire w_retire=write_rsp.valid && write_rsp.ready;
    assign write_req.ready=rst_n && w_count<WCNT'(WRITE_DEPTH);
    assign wa=host_writes[w_issue].addr; assign wd=host_writes[w_issue].data;
    assign wt=host_writes[w_issue].tag; assign we=host_writes[w_issue].epoch;
    assign wr_sel=host_writes[w_issue].device; assign wr_bad=host_writes[w_issue].bad;
    assign read_rsp.valid=rst_n && rs==REPLY;
    assign read_rsp.addr=ra; assign read_rsp.data=rdata;
    assign read_rsp.tag=rt; assign read_rsp.epoch=re;
    assign write_rsp.valid=rst_n && w_count!=0 && host_complete[w_head];
    assign write_rsp.addr=host_writes[w_head].addr;
    assign write_rsp.data=host_status[w_head];
    assign write_rsp.tag=host_writes[w_head].tag;
    assign write_rsp.epoch=host_writes[w_head].epoch;
    assign fault=sch_fault || host_fault || (done && acc_unflushed);
    assign ar[0].valid=rst_n && rs==ISSUE && !rd_bad && rd_sel==2'd0;
    assign ar[0].addr=ra;
    assign ar[0].data=0;
    assign ar[0].tag=rt; assign ar[0].epoch=re;
    assign ir[0].valid=rst_n && rs==ISSUE && !rd_bad && rd_sel==2'd1;
    assign ir[0].addr=ra;
    assign ir[0].data=0;
    assign ir[0].tag=rt; assign ir[0].epoch=re;
    assign cr[0].valid=rst_n && rs==ISSUE && !rd_bad && rd_sel==2'd3;
    assign cr[0].addr=ra;
    assign cr[0].data=0;
    assign cr[0].tag=rt; assign cr[0].epoch=re;
    assign aw[0].valid=rst_n && w_queued!=0 && !wr_bad && wr_sel==2'd0;
    assign aw[0].addr=wa;
    assign aw[0].data=128'(wd);
    assign aw[0].tag=4'(w_issue); assign aw[0].epoch=we;
    assign iw[0].valid=rst_n && w_queued!=0 && !wr_bad && wr_sel==2'd1;
    assign iw[0].addr=wa;
    assign iw[0].data=32'(wd);
    assign iw[0].tag=4'(w_issue); assign iw[0].epoch=we;
    assign sch_wr.valid=rst_n && !busy && (kick_pending || (w_queued!=0 && !wr_bad && wr_sel==2'd2 && w_issue==w_head));
    assign sch_wr.addr=kick_pending ? 32'h80080 : wa;
    assign sch_wr.data=kick_pending ? 128'(kick_pc) : wd;
    assign sch_wr.tag=wt; assign sch_wr.epoch=we;
    assign cw[0].valid=rst_n && w_queued!=0 && !wr_bad && wr_sel==2'd3;
    assign cw[0].addr=wa;
    assign cw[0].data=128'(wd);
    assign cw[0].tag=4'(w_issue); assign cw[0].epoch=we;
    assign ap[0].ready=rst_n && rs==WAIT_RSP && rd_sel==2'd0;
    assign ip[0].ready=rst_n && rs==WAIT_RSP && rd_sel==2'd1;
    assign cp[0].ready=rst_n && rs==WAIT_RSP && rd_sel==2'd3;
    assign ab[0].ready=rst_n;
    assign ib[0].ready=rst_n;
    assign cb[0].ready=rst_n;
    banked_bram_with_rsp #(.READ_PORTS(3),.WRITE_PORTS(1),.WORDS_PER_BANK(WORDS_PER_BANK)) mem_a(
        .clk(clk),.rst_n(rst_n),.read_req(ar),.read_rsp(ap),.write_req(aw),.write_rsp(ab));
    banked_bram_with_rsp #(.READ_PORTS(2),.WRITE_PORTS(2),.WORDS_PER_BANK(WORDS_PER_BANK)) mem_c(
        .clk(clk),.rst_n(rst_n),.read_req(cr),.read_rsp(cp),.write_req(cw),.write_rsp(cb));
    banked_bram_with_rsp #(.READ_PORTS(2),.WRITE_PORTS(1),.DATA_WIDTH(32),.WORDS_PER_BANK(WORDS_PER_BANK)) instructions(
        .clk(clk),.rst_n(rst_n),.read_req(ir),.read_rsp(ip),.write_req(iw),.write_rsp(ib));
    // Internal instruction interfaces are 128-bit in sch, while memory is 32-bit.
    rv_if #(.DATA_WIDTH(128)) fetch_req(), fetch_rsp();
    assign ir[1].valid=fetch_req.valid;
    assign ir[1].addr=fetch_req.addr;
    assign ir[1].data=32'(fetch_req.data);
    assign ir[1].tag=fetch_req.tag;
    assign ir[1].epoch=fetch_req.epoch;
    assign fetch_req.ready=ir[1].ready;
    assign fetch_rsp.valid=ip[1].valid;
    assign fetch_rsp.addr=ip[1].addr;
    assign fetch_rsp.data=128'(ip[1].data);
    assign fetch_rsp.tag=ip[1].tag;
    assign fetch_rsp.epoch=ip[1].epoch;
    assign ip[1].ready=fetch_rsp.ready;
    sch scheduler(.clk(clk),.rst_n(rst_n),.write_req(sch_wr),
        .mem_read_req(fetch_req),.mem_read_rsp(fetch_rsp),.dma_ctrl(controls),
        .vector_control_req(operands[3]),.running(running),.fault(sch_fault));
    dma #(.ADDR_WIDTH(32),.DATA_WIDTH(128)) operand_dma_0(
        .clk(clk),.rst_n(rst_n),.read_req(ar[1]),.read_rsp(ap[1]),
        .write_req(operands[0]),.ctrl(controls[0]));
    assign dma_idle[0]=controls[0].ready;
    dma #(.ADDR_WIDTH(32),.DATA_WIDTH(128)) operand_dma_1(
        .clk(clk),.rst_n(rst_n),.read_req(ar[2]),.read_rsp(ap[2]),
        .write_req(operands[1]),.ctrl(controls[1]));
    assign dma_idle[1]=controls[1].ready;
    dma #(.ADDR_WIDTH(32),.DATA_WIDTH(128)) operand_dma_2(
        .clk(clk),.rst_n(rst_n),.read_req(cr[1]),.read_rsp(cp[1]),
        .write_req(operands[2]),.ctrl(controls[2]));
    assign dma_idle[2]=controls[2].ready;
    handshake_join #(.ADDR_WIDTH(32),.DATA_WIDTH(128),.N(4),.ADDR_SEL(3)) join_operands(
        .clk(clk),.rst_n(rst_n),.in_ch(operands),.out_ch(joined));
    vector_alu #(.DATA_WIDTH(8),.RESULT_WIDTH(16),.LANE_SIZE(16)) alu(
        .clk(clk),.rst_n(rst_n),.in_ch(joined),.out_ch(raw),.done(alu_done));
    rv_if #(.DATA_WIDTH(272)) accumulate_input();
    rv_pipe_fifo #(.DATA_WIDTH(272)) alu_boundary(
        .clk(clk),.rst_n(rst_n),.in_ch(raw),.out_ch(accumulate_input));
    vector_accumulate_slot accumulator(.clk(clk),.rst_n(rst_n),
        .data(accumulate_input),.out_ch(results));
    rv_if #(.DATA_WIDTH(128)) result_pipe();
    rv_pipe_fifo #(.DATA_WIDTH(128)) result_boundary(
        .clk(clk),.rst_n(rst_n),.in_ch(results),.out_ch(result_pipe));
    assign cw[1].valid=result_pipe.valid;
    assign cw[1].addr=result_pipe.addr;
    assign cw[1].data=result_pipe.data;
    assign cw[1].tag=result_pipe.tag;
    assign cw[1].epoch=result_pipe.epoch;
    assign result_pipe.ready=cw[1].ready;
    assign cb[1].ready=1;
    wire issued_control=operands[3].valid && operands[3].ready;
    wire issued_flush=issued_control && !operands[3].data[6];
    wire committed_flush=cb[1].valid && cb[1].ready;
    wire start=sch_wr.valid && sch_wr.ready && sch_wr.addr[17:0]==18'h80 && sch_wr.data[1:0]==0;
    always_ff @(posedge clk) begin
        if(!rst_n) begin kick_pending<=0; kick_pc<=0; end
        else begin
            if(launch) begin kick_pending<=1; kick_pc<=launch_pc; end
            if(kick_pending && sch_wr.valid && sch_wr.ready) kick_pending<=0;
        end
    end
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            busy<=0; done<=0; host_fault<=0; acc_unflushed<=0; flushes<=0;
        end else begin
            case({issued_flush,committed_flush})
                2'b10:flushes<=flushes+1'b1;
                2'b01:flushes<=flushes-1'b1;
                default:;
            endcase
            if(issued_control) acc_unflushed<=operands[3].data[6];
            if(start) begin busy<=1; done<=0; acc_unflushed<=0; end
            else if(busy && !running && (&dma_idle) && flushes==0) begin busy<=0; done<=1; end
            if((rs==ISSUE && rd_bad)||(w_issue_fire && wr_bad)) host_fault<=1;
        end
    end
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            rs<=IDLE; ra<=0; rdata<=0;
            rt<=0; re<=0; rd_sel<=0; rd_bad<=0;
        end else begin
            case(rs)
                IDLE:if(read_req.valid && read_req.ready) begin
                    ra<=read_req.addr; rt<=read_req.tag; re<=read_req.epoch;
                    rd_sel<=read_req.addr[19:18]; rd_bad<=!valid_read(read_req.addr); rs<=ISSUE;
                end
                ISSUE:begin
                    if(rd_bad) begin rdata<=0; rs<=REPLY; end
                    else case(rd_sel)
                        0:if(ar[0].ready) rs<=WAIT_RSP;
                        1:if(ir[0].ready) rs<=WAIT_RSP;
                        2:begin rdata<={125'b0,fault,done,busy}; rs<=REPLY; end
                        3:if(cr[0].ready) rs<=WAIT_RSP;
                    endcase
                end
                WAIT_RSP:case(rd_sel)
                    0:if(ap[0].valid) begin rdata<=ap[0].data; rs<=REPLY; end
                    1:if(ip[0].valid) begin rdata<=128'(ip[0].data); rs<=REPLY; end
                    3:if(cp[0].valid) begin rdata<=cp[0].data; rs<=REPLY; end
                    default:rs<=REPLY;
                endcase
                REPLY:if(read_rsp.ready) rs<=IDLE;
            endcase
        end
    end
    always_comb begin
        w_issue_fire=0;
        if(rst_n && w_queued!=0) begin
            if(wr_bad) w_issue_fire=1;
            else case(wr_sel)
                0:w_issue_fire=aw[0].valid && aw[0].ready;
                1:w_issue_fire=iw[0].valid && iw[0].ready;
                2:w_issue_fire=sch_wr.valid && sch_wr.ready && !kick_pending;
                3:w_issue_fire=cw[0].valid && cw[0].ready;
            endcase
        end
    end
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            w_tail<=0; w_issue<=0; w_head<=0; w_count<=0; w_queued<=0;
            host_complete<=0; host_live<=0; host_sent<=0;
        end else begin
            if(w_accept) begin
                host_writes[w_tail]<='{addr:write_req.addr,data:write_req.data,
                    tag:write_req.tag,epoch:write_req.epoch,device:write_req.addr[19:18],
                    bad:!valid_write(write_req.addr) || (write_req.addr==32'h80080 && write_req.data[1:0]!=0)};
                host_complete[w_tail]<=0; host_live[w_tail]<=1; host_sent[w_tail]<=0;
                w_tail<=next_write(w_tail);
            end
            if(w_issue_fire) begin
                host_sent[w_issue]<=1;
                if(wr_bad || wr_sel==2) begin
                    host_complete[w_issue]<=1; host_status[w_issue]<=wr_bad ? 128'd1 : 128'd0;
                end
                w_issue<=next_write(w_issue);
            end
            if(ab[0].valid && ab[0].ready) begin host_complete[WPTR'(ab[0].tag)]<=1; host_status[WPTR'(ab[0].tag)]<=ab[0].data; end
            if(ib[0].valid && ib[0].ready) begin host_complete[WPTR'(ib[0].tag)]<=1; host_status[WPTR'(ib[0].tag)]<=128'(ib[0].data); end
            if(cb[0].valid && cb[0].ready) begin host_complete[WPTR'(cb[0].tag)]<=1; host_status[WPTR'(cb[0].tag)]<=cb[0].data; end
            if(w_retire) begin host_live[w_head]<=0; w_head<=next_write(w_head); end
            case({w_accept,w_retire})
                2'b10:w_count<=w_count+1'b1;
                2'b01:w_count<=w_count-1'b1;
                default:;
            endcase
            case({w_accept,w_issue_fire})
                2'b10:w_queued<=w_queued+1'b1;
                2'b01:w_queued<=w_queued-1'b1;
                default:;
            endcase
        end
    end
    initial if(WRITE_DEPTH<1 || WRITE_DEPTH>16 || (WRITE_DEPTH & (WRITE_DEPTH-1))!=0)
        $fatal(1,"vector_tile_core WRITE_DEPTH must be a power of two in 1..16");
    // synthesis translate_off
    always @(posedge clk) if(rst_n) begin
        if(ab[0].valid && ab[0].ready)
            assert(int'(ab[0].tag)<WRITE_DEPTH && host_live[WPTR'(ab[0].tag)] && host_sent[WPTR'(ab[0].tag)] &&
                host_writes[WPTR'(ab[0].tag)].device==0 && ab[0].addr==host_writes[WPTR'(ab[0].tag)].addr &&
                ab[0].epoch==host_writes[WPTR'(ab[0].tag)].epoch && !host_complete[WPTR'(ab[0].tag)]);
        if(ib[0].valid && ib[0].ready)
            assert(int'(ib[0].tag)<WRITE_DEPTH && host_live[WPTR'(ib[0].tag)] && host_sent[WPTR'(ib[0].tag)] &&
                host_writes[WPTR'(ib[0].tag)].device==1 && ib[0].addr==host_writes[WPTR'(ib[0].tag)].addr &&
                ib[0].epoch==host_writes[WPTR'(ib[0].tag)].epoch && !host_complete[WPTR'(ib[0].tag)]);
        if(cb[0].valid && cb[0].ready)
            assert(int'(cb[0].tag)<WRITE_DEPTH && host_live[WPTR'(cb[0].tag)] && host_sent[WPTR'(cb[0].tag)] &&
                host_writes[WPTR'(cb[0].tag)].device==3 && cb[0].addr==host_writes[WPTR'(cb[0].tag)].addr &&
                cb[0].epoch==host_writes[WPTR'(cb[0].tag)].epoch && !host_complete[WPTR'(cb[0].tag)]);
    end
    // synthesis translate_on
endmodule
