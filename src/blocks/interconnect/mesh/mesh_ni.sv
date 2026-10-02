// Up to WRITE_DEPTH writes in flight, beat ACKs retained. Reads are serialized
// and fence outstanding writes. A write window targets one tile at a time.
// Network write tags are allocated slot IDs; client tag/epoch are restored.
// Requests/replies have registered launch stages; ready uses local occupancy.
module mesh_ni #(parameter int X=0, Y=0, WRITE_DEPTH=8)(
    input logic clk, rst_n,
    rv_if.sink read_req, write_req,
    rv_if.source read_rsp, write_rsp,
    rv_if.source target_read_req, target_write_req,
    rv_if.sink target_read_rsp, target_write_rsp,
    rv_if.source req_tx, rsp_tx,
    rv_if.sink req_rx, rsp_rx
);
    localparam int PTR=WRITE_DEPTH>1 ? $clog2(WRITE_DEPTH) : 1;
    localparam int CNT=$clog2(WRITE_DEPTH+1);
    function automatic logic [PTR-1:0] next_slot(input logic [PTR-1:0] p);
        return p==PTR'(WRITE_DEPTH-1) ? '0 : p+1'b1;
    endfunction
    typedef struct packed {
        logic [31:0] addr;
        logic [127:0] data;
        logic [3:0] tag, epoch;
    } payload_t;
    payload_t outgoing[WRITE_DEPTH], incoming[WRITE_DEPTH];
    logic [3:0] incoming_source[WRITE_DEPTH];
    logic [127:0] out_status[WRITE_DEPTH], in_status[WRITE_DEPTH];
    logic [WRITE_DEPTH-1:0] out_done, out_sent, out_live, in_done;
    logic [PTR-1:0] out_tail, out_issue, out_head;
    logic [PTR-1:0] in_tail, in_issue, in_complete, in_head;
    logic [CNT-1:0] out_count, out_queued, in_count, in_queued, in_issued;
    logic [3:0] destination;
    typedef enum logic [1:0] {R_IDLE, R_SEND, R_WAIT, R_REPLY} read_state_t;
    read_state_t ro, ri;
    payload_t outgoing_read, incoming_read;
    logic [3:0] read_source;
    logic [127:0] read_data, target_read_data;
    logic read_sent;
    logic [PTR-1:0] tx_slot;
    logic tx_write;

    wire accept_write=write_req.valid && write_req.ready;
    wire consume_write=write_rsp.valid && write_rsp.ready;
    wire accept_in=req_rx.valid && req_rx.ready && req_rx.data[132];
    wire issue_in=target_write_req.valid && target_write_req.ready;
    wire complete_in=target_write_rsp.valid && target_write_rsp.ready;
    wire launch_space=!req_tx.valid || req_tx.ready;
    wire launch_write=rst_n && launch_space && out_queued!=0;
    wire launch_read=rst_n && launch_space && out_queued==0 && ro==R_SEND;
    wire reply_space=!rsp_tx.valid || rsp_tx.ready;
    wire reply_write=rst_n && reply_space && in_count!=0 && in_done[in_head];
    wire reply_read=rst_n && reply_space && !reply_write && ri==R_REPLY;
    wire receive_write=rsp_rx.valid && rsp_rx.ready && rsp_rx.data[132];
    logic [PTR-1:0] received_slot;
    assign received_slot=PTR'(rsp_rx.tag);

    assign write_req.ready=rst_n && ro==R_IDLE && out_count<CNT'(WRITE_DEPTH) &&
        (out_count==0 || write_req.addr[31:28]==destination);
    assign read_req.ready=rst_n && ro==R_IDLE && out_count==0 && !write_req.valid;
    assign write_rsp.valid=rst_n && out_count!=0 && out_done[out_head];
    assign write_rsp.addr=outgoing[out_head].addr;
    assign write_rsp.data=out_status[out_head];
    assign write_rsp.tag=outgoing[out_head].tag;
    assign write_rsp.epoch=outgoing[out_head].epoch;
    assign read_rsp.valid=rst_n && ro==R_REPLY;
    assign read_rsp.addr=outgoing_read.addr;
    assign read_rsp.data=read_data;
    assign read_rsp.tag=outgoing_read.tag;
    assign read_rsp.epoch=outgoing_read.epoch;
    // Every accepted write already reserved its response slot. Reception does
    // not depend on client write_rsp.ready; even reordered ACKs fit.
    assign rsp_rx.ready=rst_n && (rsp_rx.data[132] ?
        (int'(rsp_rx.tag)<WRITE_DEPTH && out_live[received_slot] &&
         out_sent[received_slot] && !out_done[received_slot]) : ro==R_WAIT);

    assign req_rx.ready=rst_n && ri==R_IDLE && (req_rx.data[132] ?
        in_count<CNT'(WRITE_DEPTH) : in_count==0);
    assign target_write_req.valid=rst_n && in_queued!=0;
    assign target_write_req.addr={4'b0,incoming[in_issue].addr[27:0]};
    assign target_write_req.data=incoming[in_issue].data;
    assign target_write_req.tag=incoming[in_issue].tag;
    assign target_write_req.epoch=incoming[in_issue].epoch;
    // Endpoint responses must follow accepted write order. vector_tile/core
    // explicitly reorder their memory-port completions to satisfy this contract.
    assign target_write_rsp.ready=rst_n && in_issued!=0;
    assign target_read_req.valid=rst_n && ri==R_SEND;
    assign target_read_req.addr={4'b0,incoming_read.addr[27:0]};
    assign target_read_req.data=0;
    assign target_read_req.tag=incoming_read.tag;
    assign target_read_req.epoch=incoming_read.epoch;
    assign target_read_rsp.ready=rst_n && ri==R_WAIT;

    always_ff @(posedge clk) begin
        if(!rst_n) begin
            out_tail<=0; out_issue<=0; out_head<=0; out_count<=0; out_queued<=0;
            in_tail<=0; in_issue<=0; in_complete<=0; in_head<=0;
            in_count<=0; in_queued<=0; in_issued<=0;
            out_done<=0; out_sent<=0; out_live<=0; in_done<=0; destination<=0;
            ro<=R_IDLE; ri<=R_IDLE; outgoing_read<='0; incoming_read<='0;
            read_data<=0; target_read_data<=0; read_source<=0; read_sent<=0;
            req_tx.valid<=0; req_tx.addr<=0; req_tx.data<=0; req_tx.tag<=0; req_tx.epoch<=0;
            rsp_tx.valid<=0; rsp_tx.addr<=0; rsp_tx.data<=0; rsp_tx.tag<=0; rsp_tx.epoch<=0;
            tx_slot<=0; tx_write<=0;
        end else begin
            if(accept_write) begin
                outgoing[out_tail]<='{addr:write_req.addr,data:write_req.data,
                    tag:write_req.tag,epoch:write_req.epoch};
                out_live[out_tail]<=1; out_done[out_tail]<=0; out_sent[out_tail]<=0;
                out_tail<=next_slot(out_tail);
                if(out_count==0) destination<=write_req.addr[31:28];
            end
            if(consume_write) begin out_live[out_head]<=0; out_head<=next_slot(out_head); end
            case({accept_write,consume_write})
                2'b10:out_count<=out_count+1'b1;
                2'b01:out_count<=out_count-1'b1;
                default:;
            endcase
            case({accept_write,launch_write})
                2'b10:out_queued<=out_queued+1'b1;
                2'b01:out_queued<=out_queued-1'b1;
                default:;
            endcase
            if(req_tx.valid && req_tx.ready) begin
                req_tx.valid<=0;
                if(tx_write) out_sent[tx_slot]<=1;
                else read_sent<=1;
            end
            if(launch_write) begin
                req_tx.valid<=1; req_tx.addr<=outgoing[out_issue].addr;
                req_tx.data<={1'b1,2'(X),2'(Y),outgoing[out_issue].data};
                req_tx.tag<=4'(out_issue); req_tx.epoch<=outgoing[out_issue].epoch;
                tx_slot<=out_issue; tx_write<=1; out_issue<=next_slot(out_issue);
            end else if(launch_read) begin
                req_tx.valid<=1; req_tx.addr<=outgoing_read.addr;
                req_tx.data<={1'b0,2'(X),2'(Y),128'b0};
                req_tx.tag<=outgoing_read.tag; req_tx.epoch<=outgoing_read.epoch;
                tx_write<=0; ro<=R_WAIT;
            end
            if(read_req.valid && read_req.ready) begin
                outgoing_read<='{addr:read_req.addr,data:128'b0,tag:read_req.tag,epoch:read_req.epoch};
                ro<=R_SEND; read_sent<=0;
            end
            if(receive_write) begin
                out_status[received_slot]<=rsp_rx.data[127:0]; out_done[received_slot]<=1;
            end
            if(rsp_rx.valid && rsp_rx.ready && !rsp_rx.data[132]) begin
                read_data<=rsp_rx.data[127:0]; ro<=R_REPLY;
            end
            if(read_rsp.valid && read_rsp.ready) ro<=R_IDLE;

            if(accept_in) begin
                incoming[in_tail]<='{addr:req_rx.addr,data:req_rx.data[127:0],tag:req_rx.tag,epoch:req_rx.epoch};
                incoming_source[in_tail]<=req_rx.data[131:128];
                in_done[in_tail]<=0; in_tail<=next_slot(in_tail);
            end
            if(issue_in) in_issue<=next_slot(in_issue);
            if(complete_in) begin
                in_status[in_complete]<=target_write_rsp.data;
                in_done[in_complete]<=1; in_complete<=next_slot(in_complete);
            end
            case({accept_in,reply_write})
                2'b10:in_count<=in_count+1'b1;
                2'b01:in_count<=in_count-1'b1;
                default:;
            endcase
            case({accept_in,issue_in})
                2'b10:in_queued<=in_queued+1'b1;
                2'b01:in_queued<=in_queued-1'b1;
                default:;
            endcase
            case({issue_in,complete_in})
                2'b10:in_issued<=in_issued+1'b1;
                2'b01:in_issued<=in_issued-1'b1;
                default:;
            endcase
            if(req_rx.valid && req_rx.ready && !req_rx.data[132]) begin
                incoming_read<='{addr:req_rx.addr,data:128'b0,tag:req_rx.tag,epoch:req_rx.epoch};
                read_source<=req_rx.data[131:128]; ri<=R_SEND;
            end
            if(target_read_req.valid && target_read_req.ready) ri<=R_WAIT;
            if(target_read_rsp.valid && target_read_rsp.ready) begin target_read_data<=target_read_rsp.data; ri<=R_REPLY; end
            if(rsp_tx.valid && rsp_tx.ready) rsp_tx.valid<=0;
            if(reply_write) begin
                rsp_tx.valid<=1;
                rsp_tx.addr<={incoming_source[in_head],incoming[in_head].addr[27:0]};
                rsp_tx.data<={1'b1,4'b0,in_status[in_head]};
                rsp_tx.tag<=incoming[in_head].tag; rsp_tx.epoch<=incoming[in_head].epoch;
                in_head<=next_slot(in_head);
            end else if(reply_read) begin
                rsp_tx.valid<=1; rsp_tx.addr<={read_source,incoming_read.addr[27:0]};
                rsp_tx.data<={1'b0,4'b0,target_read_data};
                rsp_tx.tag<=incoming_read.tag; rsp_tx.epoch<=incoming_read.epoch; ri<=R_IDLE;
            end
        end
    end
    initial if(WRITE_DEPTH<1 || WRITE_DEPTH>16 || (WRITE_DEPTH & (WRITE_DEPTH-1))!=0)
        $fatal(1,"mesh_ni WRITE_DEPTH must be a power of two in 1..16");
    // synthesis translate_off
    if(WRITE_DEPTH>1) begin : occupancy_checks
        always @(posedge clk) if(rst_n)
            assert(out_count<=CNT'(WRITE_DEPTH) && in_count<=CNT'(WRITE_DEPTH));
    end
    always @(posedge clk) if(rst_n) begin
        if(receive_write)
            assert(rsp_rx.addr=={2'(X),2'(Y),outgoing[received_slot].addr[27:0]} &&
                rsp_rx.epoch==outgoing[received_slot].epoch)
                else $fatal(1,"mesh_ni write ACK identity mismatch");
        if(rsp_rx.valid && rsp_rx.ready && !rsp_rx.data[132])
            assert(read_sent && rsp_rx.addr=={2'(X),2'(Y),outgoing_read.addr[27:0]} &&
                rsp_rx.tag==outgoing_read.tag && rsp_rx.epoch==outgoing_read.epoch)
                else $fatal(1,"mesh_ni read response identity mismatch");
        if(complete_in)
            assert(target_write_rsp.addr=={4'b0,incoming[in_complete].addr[27:0]} &&
                target_write_rsp.tag==incoming[in_complete].tag && target_write_rsp.epoch==incoming[in_complete].epoch)
                else $fatal(1,"mesh_ni endpoint write response out of order");
    end
    // synthesis translate_on
endmodule
