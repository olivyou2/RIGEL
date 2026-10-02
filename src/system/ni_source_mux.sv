// Registered host/copy write queue and per-beat owner FIFO. Responses follow
// accepted order. Reads fence writes and keep one registered owner.
module ni_source_mux #(parameter int WRITE_DEPTH=8)(input logic clk, rst_n,
    rv_if.sink read_req[2], write_req[2],
    rv_if.source read_rsp[2], write_rsp[2],
    rv_if.source ni_read_req, ni_write_req,
    rv_if.sink ni_read_rsp, ni_write_rsp
);
    localparam int PTR=WRITE_DEPTH>1 ? $clog2(WRITE_DEPTH) : 1;
    localparam int CNT=$clog2(WRITE_DEPTH+1);
    function automatic logic [PTR-1:0] next_slot(input logic [PTR-1:0] p);
        return p==PTR'(WRITE_DEPTH-1) ? '0 : p+1'b1;
    endfunction
    typedef struct packed {logic [31:0] addr; logic [127:0] data; logic [3:0] tag,epoch; logic owner;} request_t;
    request_t q[WRITE_DEPTH];
    logic [PTR-1:0] tail, issue, head;
    logic [CNT-1:0] count, queued, issued;
    logic prefer;
    logic [1:0] wvalid, rvalid, wready, rready, choose;
    logic [31:0] wa[2],ra[2];
    logic [127:0] wd[2];
    logic [3:0] wt[2],we[2],rt[2],re[2];
    typedef enum logic [1:0] {R_IDLE,R_SEND,R_WAIT} read_state_t;
    read_state_t state;
    request_t read_job;
    assign choose[0]=wvalid[0] && (!wvalid[1] || !prefer);
    assign choose[1]=wvalid[1] && (!wvalid[0] || prefer);
    wire push=rst_n && state==R_IDLE && count<CNT'(WRITE_DEPTH) && |choose;
    wire send=ni_write_req.valid && ni_write_req.ready;
    wire pop=ni_write_rsp.valid && ni_write_rsp.ready;
    logic read_owner;
    assign read_owner=rvalid[1] && (!rvalid[0] || prefer);
    for(genvar i=0;i<2;i++) begin : clients
        assign wvalid[i]=write_req[i].valid; assign rvalid[i]=read_req[i].valid;
        assign wa[i]=write_req[i].addr; assign ra[i]=read_req[i].addr;
        assign wd[i]=write_req[i].data;
        assign wt[i]=write_req[i].tag; assign we[i]=write_req[i].epoch;
        assign rt[i]=read_req[i].tag; assign re[i]=read_req[i].epoch;
        assign wready[i]=write_rsp[i].ready; assign rready[i]=read_rsp[i].ready;
        assign write_req[i].ready=rst_n && state==R_IDLE && count<CNT'(WRITE_DEPTH) && choose[i];
        assign read_req[i].ready=rst_n && state==R_IDLE && count==0 && !(|wvalid) && read_owner==1'(i);
        assign write_rsp[i].valid=rst_n && issued!=0 && q[head].owner==1'(i) && ni_write_rsp.valid;
        assign write_rsp[i].addr=ni_write_rsp.addr; assign write_rsp[i].data=ni_write_rsp.data;
        assign write_rsp[i].tag=ni_write_rsp.tag; assign write_rsp[i].epoch=ni_write_rsp.epoch;
        assign read_rsp[i].valid=rst_n && state==R_WAIT && read_job.owner==1'(i) && ni_read_rsp.valid;
        assign read_rsp[i].addr=ni_read_rsp.addr; assign read_rsp[i].data=ni_read_rsp.data;
        assign read_rsp[i].tag=ni_read_rsp.tag; assign read_rsp[i].epoch=ni_read_rsp.epoch;
    end
    assign ni_write_req.valid=rst_n && queued!=0;
    assign ni_write_req.addr=q[issue].addr; assign ni_write_req.data=q[issue].data;
    assign ni_write_req.tag=q[issue].tag; assign ni_write_req.epoch=q[issue].epoch;
    assign ni_write_rsp.ready=rst_n && issued!=0 && wready[q[head].owner];
    assign ni_read_req.valid=rst_n && state==R_SEND;
    assign ni_read_req.addr=read_job.addr; assign ni_read_req.data=0;
    assign ni_read_req.tag=read_job.tag; assign ni_read_req.epoch=read_job.epoch;
    assign ni_read_rsp.ready=rst_n && state==R_WAIT && rready[read_job.owner];
    always_ff @(posedge clk) begin
        if(!rst_n) begin tail<=0; issue<=0; head<=0; count<=0; queued<=0; issued<=0; prefer<=0; state<=R_IDLE; read_job<='0; end
        else begin
            if(push) begin
                q[tail]<='{addr:wa[choose[1]],data:wd[choose[1]],tag:wt[choose[1]],epoch:we[choose[1]],owner:choose[1]};
                tail<=next_slot(tail); prefer<=!choose[1];
            end
            if(send) issue<=next_slot(issue);
            if(pop) head<=next_slot(head);
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:;
            endcase
            case({push,send})
                2'b10:queued<=queued+1'b1;
                2'b01:queued<=queued-1'b1;
                default:;
            endcase
            case({send,pop})
                2'b10:issued<=issued+1'b1;
                2'b01:issued<=issued-1'b1;
                default:;
            endcase
            case(state)
                R_IDLE:if(count==0 && !(|wvalid) && |rvalid) begin
                    read_job<='{addr:ra[read_owner],data:128'b0,tag:rt[read_owner],epoch:re[read_owner],owner:read_owner};
                    prefer<=!read_owner; state<=R_SEND;
                end
                R_SEND:if(ni_read_req.ready) state<=R_WAIT;
                R_WAIT:if(ni_read_rsp.valid && ni_read_rsp.ready) state<=R_IDLE;
                default:state<=R_IDLE;
            endcase
        end
    end
    initial if(WRITE_DEPTH<1 || WRITE_DEPTH>16 || (WRITE_DEPTH & (WRITE_DEPTH-1))!=0)
        $fatal(1,"ni_source_mux WRITE_DEPTH must be a power of two in 1..16");
    // synthesis translate_off
    always @(posedge clk) if(rst_n && pop)
        assert(ni_write_rsp.addr==q[head].addr && ni_write_rsp.tag==q[head].tag && ni_write_rsp.epoch==q[head].epoch)
            else $fatal(1,"ni_source_mux response owner/order mismatch");
    // synthesis translate_on
endmodule
