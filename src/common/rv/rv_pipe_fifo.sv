// Two-entry registered transport. Input ready depends only on occupancy;
// no downstream ready feedback. A full queue resumes one cycle after a pop.
module rv_pipe_fifo #(
    parameter int ADDR_WIDTH=32, DATA_WIDTH=128, TAG_WIDTH=4, EPOCH_WIDTH=4
)(input logic clk, rst_n, rv_if.sink in_ch, rv_if.source out_ch);
    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [TAG_WIDTH-1:0] tag;
        logic [EPOCH_WIDTH-1:0] epoch;
    } payload_t;
    payload_t q[2];
    logic head, tail;
    logic [1:0] count;
    wire push=in_ch.valid && in_ch.ready;
    wire pop=out_ch.valid && out_ch.ready;
    assign in_ch.ready=rst_n && count<2;
    assign out_ch.valid=rst_n && count!=0;
    assign out_ch.addr=q[head].addr;
    assign out_ch.data=q[head].data;
    assign out_ch.tag=q[head].tag;
    assign out_ch.epoch=q[head].epoch;
    always_ff @(posedge clk) begin
        if(!rst_n) begin head<=0; tail<=0; count<=0; end
        else begin
            if(push) begin
                q[tail]<='{addr:in_ch.addr,data:in_ch.data,tag:in_ch.tag,epoch:in_ch.epoch};
                tail<=~tail;
            end
            if(pop) head<=~head;
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: ;
            endcase
        end
    end
endmodule
