// Initial inter-tile mover: aligned 16-byte beats, read -> write -> ACK.
// Every stage is registered. Completion means the final destination write ACK.
module tile_copy_engine(
    input logic clk, rst_n, start,
    input logic [31:0] source_addr, dest_addr, length,
    output logic busy, done, fault,
    rv_if.source read_req, write_req,
    rv_if.sink read_rsp, write_rsp
);
    typedef enum logic [2:0] {IDLE, READ_SEND, READ_WAIT, WRITE_SEND, WRITE_WAIT} state_t;
    state_t state;
    logic [31:0] src, dst, remaining;
    logic [127:0] payload;
    logic [3:0] sequence_id;
    assign busy=state!=IDLE;
    assign read_req.valid=rst_n && state==READ_SEND;
    assign read_req.addr=src; assign read_req.data=0;
    assign read_req.tag=sequence_id; assign read_req.epoch=0;
    assign read_rsp.ready=rst_n && state==READ_WAIT;
    assign write_req.valid=rst_n && state==WRITE_SEND;
    assign write_req.addr=dst; assign write_req.data=payload;
    assign write_req.tag=sequence_id; assign write_req.epoch=0;
    assign write_rsp.ready=rst_n && state==WRITE_WAIT;
    always_ff @(posedge clk) begin
        if(!rst_n) begin state<=IDLE; done<=0; fault<=0; src<=0; dst<=0; remaining<=0; payload<=0; sequence_id<=0; end
        else case(state)
            IDLE:if(start) begin
                done<=0; fault<=0; src<=source_addr; dst<=dest_addr; remaining<=length; sequence_id<=0;
                if(source_addr[3:0]!=0 || dest_addr[3:0]!=0 || length[3:0]!=0) begin fault<=1; done<=1; end
                else if(length==0) done<=1;
                else state<=READ_SEND;
            end
            READ_SEND:if(read_req.ready) state<=READ_WAIT;
            READ_WAIT:if(read_rsp.valid) begin payload<=read_rsp.data; state<=WRITE_SEND; end
            WRITE_SEND:if(write_req.ready) state<=WRITE_WAIT;
            WRITE_WAIT:if(write_rsp.valid) begin
                if(write_rsp.data!=0) begin fault<=1; done<=1; state<=IDLE; end
                else if(remaining==16) begin done<=1; state<=IDLE; end
                else begin
                    src<=src+16; dst<=dst+16; remaining<=remaining-16;
                    sequence_id<=sequence_id+1'b1; state<=READ_SEND;
                end
            end
            default:state<=IDLE;
        endcase
    end
endmodule
