// Fixed placement, per-tile FIFO; single registered round-robin issue scanner.
// IDs cannot be reused until reset. Dependencies must be submitted first.
module mesh_task_scheduler #(parameter int QUEUE_DEPTH=4)(
    input logic clk, rst_n,
    input logic task_valid, output logic task_ready,
    input logic [7:0] task_id, task_dependency,
    input logic task_has_dependency, task_has_copy, task_copy_only,
    input logic [3:0] task_tile,
    input logic [31:0] task_pc, task_src, task_dst, task_bytes,
    output logic submit_error,
    input logic [15:0] tile_busy, tile_done, tile_fault,
    output logic [15:0] reserved, launch,
    output logic [31:0] launch_pc,
    output logic copy_valid, input logic copy_ready,
    output logic [3:0] copy_tile,
    output logic [31:0] copy_src, copy_dst, copy_bytes,
    input logic copy_done, copy_error,
    output logic completion_valid, input logic completion_ready,
    output logic [7:0] completion_id,
    output logic [3:0] completion_tile,
    output logic completion_error,
    output logic [255:0] completed, failed
);
    localparam int PW=(QUEUE_DEPTH<2)?1:$clog2(QUEUE_DEPTH);
    localparam int CW=$clog2(QUEUE_DEPTH+1);
    typedef struct packed {
        logic [7:0] id, dep;
        logic has_dep, has_copy, copy_only;
        logic [31:0] pc, src, dst, bytes;
    } descriptor_t;
    descriptor_t queue[16][QUEUE_DEPTH];
    logic [PW-1:0] head[16], tail[16];
    logic [CW-1:0] count[16];
    logic [255:0] submitted;
    logic [3:0] scan, selected;
    descriptor_t candidate, transfer;
    logic candidate_valid, copy_busy, copy_pending, copy_waiting, copy_finished, copy_failed;
    logic [3:0] transfer_tile;
    logic [31:0] start_pc;
    logic [15:0] running, armed, finishing, errors;
    logic [7:0] active_id[16];
    typedef enum logic [2:0] {SCAN, CHECK, START} state_t;
    state_t state;
    function automatic logic [PW-1:0] advance(input logic [PW-1:0] ptr);
        return ptr==PW'(QUEUE_DEPTH-1)?'0:ptr+1'b1;
    endfunction
    assign task_ready=rst_n && count[task_tile]<CW'(QUEUE_DEPTH);
    wire accept=task_valid && task_ready;
    wire invalid_task=submitted[task_id] || (!task_copy_only && task_pc[1:0]!=0) ||
        (task_copy_only && !task_has_copy) ||
        (task_has_dependency && (!submitted[task_dependency] || task_dependency==task_id)) ||
        (task_has_copy && (task_bytes==0 || task_bytes[3:0]!=0 || task_src[3:0]!=0 || task_dst[3:0]!=0));
    wire pop=(state==CHECK && candidate_valid && count[selected]!=0 && !reserved[selected] && !tile_busy[selected] &&
        (!candidate.has_dep || completed[candidate.dep] || failed[candidate.dep]) &&
        (!candidate.has_copy || !copy_busy || (candidate.has_dep && failed[candidate.dep])));
    assign copy_valid=rst_n && copy_pending;
    assign copy_tile=transfer_tile;
    assign copy_src=transfer.src;
    assign copy_dst=transfer.dst;
    assign copy_bytes=transfer.bytes;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            state<=SCAN; scan<=0; selected<=0; candidate<='0; transfer<='0; candidate_valid<=0;
            copy_busy<=0; copy_pending<=0; copy_waiting<=0; copy_finished<=0; copy_failed<=0; transfer_tile<=0; start_pc<=0;
            submitted<=0; completed<=0; failed<=0; reserved<=0;
            running<=0; armed<=0; finishing<=0; errors<=0;
            launch<=0; launch_pc<=0; submit_error<=0;
            completion_valid<=0; completion_id<=0; completion_tile<=0; completion_error<=0;
            for(int t=0;t<16;t++) begin head[t]<=0; tail[t]<=0; count[t]<=0; active_id[t]<=0; end
        end else begin
            launch<=0; submit_error<=0;
            if(copy_valid && copy_ready) begin copy_pending<=0; copy_waiting<=1; end
            if(copy_waiting && copy_done) begin copy_waiting<=0; copy_finished<=1; copy_failed<=copy_error; end
            if(accept) begin
                if(invalid_task) submit_error<=1;
                else begin
                    queue[task_tile][tail[task_tile]]<='{task_id,task_dependency,task_has_dependency,
                        task_has_copy,task_copy_only,task_pc,task_src,task_dst,task_bytes};
                    tail[task_tile]<=advance(tail[task_tile]); submitted[task_id]<=1;
                end
            end
            for(int t=0;t<16;t++) begin
                case({accept && !invalid_task && task_tile==4'(t),pop && selected==4'(t)})
                    2'b10:count[t]<=count[t]+1'b1;
                    2'b01:count[t]<=count[t]-1'b1;
                    default:;
                endcase
                if(running[t] && tile_busy[t]) armed[t]<=1;
                if(running[t] && armed[t] && !tile_busy[t] && (tile_done[t] || tile_fault[t])) begin
                    running[t]<=0; finishing[t]<=1; errors[t]<=tile_fault[t];
                end
            end
            // One completion buffer; reservations remain until the consumer retires it.
            if(completion_valid && completion_ready) begin
                completion_valid<=0; reserved[completion_tile]<=0;
                if(completion_error) failed[completion_id]<=1;
                else completed[completion_id]<=1;
            end
            case(state)
                SCAN: if(copy_finished) begin
                    copy_finished<=0; copy_busy<=0;
                    if(copy_failed || transfer.copy_only) begin
                        finishing[transfer_tile]<=1; errors[transfer_tile]<=copy_failed;
                    end else begin
                        launch[transfer_tile]<=1; launch_pc<=transfer.pc;
                        running[transfer_tile]<=1; armed[transfer_tile]<=0;
                    end
                end else begin
                    selected<=scan; candidate<=queue[scan][head[scan]]; candidate_valid<=count[scan]!=0;
                    scan<=scan+1'b1; state<=CHECK;
                end
                CHECK: begin
                    state<=SCAN;
                    if(!completion_valid && finishing[selected]) begin
                        completion_valid<=1; completion_id<=active_id[selected];
                        completion_tile<=selected; completion_error<=errors[selected]; finishing[selected]<=0;
                    end else if(pop) begin
                        head[selected]<=advance(head[selected]); reserved[selected]<=1;
                        active_id[selected]<=candidate.id; start_pc<=candidate.pc;
                        if(tile_fault[selected] || (candidate.has_dep && failed[candidate.dep])) begin
                            finishing[selected]<=1; errors[selected]<=1;
                        end else if(candidate.has_copy) begin
                            transfer<=candidate; transfer_tile<=selected;
                            copy_busy<=1; copy_pending<=1;
                        end
                        else state<=START;
                    end
                end
                START: begin
                    launch[selected]<=1; launch_pc<=start_pc;
                    running[selected]<=1; armed[selected]<=0; state<=SCAN;
                end
                default:state<=SCAN;
            endcase
        end
    end
    initial assert(QUEUE_DEPTH>=1);
endmodule
