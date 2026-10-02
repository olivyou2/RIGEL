// Ports: local=0, east=1, west=2, south=3, north=4.
// Registered input route decode -> 5x5 RR crossbar -> registered output queues.
// X dimension is completed before Y; there are no wraparound links.
module mesh_xy_router #(
    parameter int DATA_WIDTH=133, X=0, Y=0
)(input logic clk, rst_n, rv_if.sink in_ch[5], rv_if.source out_ch[5]);
    typedef struct packed {
        logic [31:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [3:0] tag, epoch;
        logic [2:0] route;
    } packet_t;
    packet_t q[5][2];
    logic [4:0] head, tail;
    logic [1:0] count[5];
    logic [2:0] rr[5];
    logic [4:0] eligible[5], grant[5];
    rv_if #(.DATA_WIDTH(DATA_WIDTH)) selected[5]();
    function automatic logic [2:0] route(input logic [31:0] addr);
        logic signed [2:0] dx, dy;
        dx=$signed({1'b0,addr[31:30]})-3'(X);
        dy=$signed({1'b0,addr[29:28]})-3'(Y);
        if(dx!=0) return dx[2] ? 3'd2 : 3'd1;
        if(dy!=0) return dy[2] ? 3'd4 : 3'd3;
        return 3'd0;
    endfunction
    always_comb begin
        for(int o=0;o<5;o++) begin
            eligible[o]='0; grant[o]='0;
            for(int i=0;i<5;i++) eligible[o][i]=count[i]!=0 && q[i][head[i]].route==3'(o);
            // Parallel rank comparisons rather than a serial payload priority mux.
            for(int i=0;i<5;i++) begin
                grant[o][i]=eligible[o][i];
                for(int k=0;k<5;k++)
                    if(k!=i && ((3'(k)>=rr[o] && 3'(i)<rr[o]) ||
                       ((3'(k)>=rr[o])==(3'(i)>=rr[o]) && k<i)))
                        grant[o][i] &= !eligible[o][k];
            end
        end
    end
    for(genvar o=0;o<5;o++) begin : outputs
        logic [31:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [3:0] tag, epoch;
        always_comb begin
            addr='0; data='0; tag='0; epoch='0;
            for(int i=0;i<5;i++) if(grant[o][i]) begin
                addr |= q[i][head[i]].addr;
                data |= q[i][head[i]].data;
                tag |= q[i][head[i]].tag;
                epoch |= q[i][head[i]].epoch;
            end
        end
        assign selected[o].valid=rst_n && |grant[o];
        assign selected[o].addr=addr;
        assign selected[o].data=data;
        assign selected[o].tag=tag;
        assign selected[o].epoch=epoch;
        rv_pipe_fifo #(.DATA_WIDTH(DATA_WIDTH)) output_queue(
            .clk(clk),.rst_n(rst_n),.in_ch(selected[o]),.out_ch(out_ch[o]));
        always_ff @(posedge clk) begin
            if(!rst_n) rr[o]<=0;
            else if(selected[o].valid && selected[o].ready)
                for(int i=0;i<5;i++) if(grant[o][i]) rr[o]<=i==4 ? 3'd0 : 3'(i+1);
        end
    end
    // Flatten queue-ready signals before variable-index arbitration bookkeeping.
    logic [4:0] selected_ready;
    for(genvar o=0;o<5;o++) assign selected_ready[o]=selected[o].ready;
    for(genvar i=0;i<5;i++) begin : inputs
        wire push=in_ch[i].valid && in_ch[i].ready;
        logic pop;
        always_comb begin
            pop=0;
            for(int o=0;o<5;o++) pop |= grant[o][i] && selected_ready[o];
        end
        assign in_ch[i].ready=rst_n && count[i]<2;
        always_ff @(posedge clk) begin
            if(!rst_n) begin count[i]<=0; head[i]<=0; tail[i]<=0; end
            else begin
                if(push) begin
                    q[i][tail[i]] <= '{addr:in_ch[i].addr,data:in_ch[i].data,
                        tag:in_ch[i].tag,epoch:in_ch[i].epoch,route:route(in_ch[i].addr)};
                    tail[i]<=~tail[i];
                end
                if(pop) head[i]<=~head[i];
                case({push,pop})
                    2'b10:count[i]<=count[i]+1'b1;
                    2'b01:count[i]<=count[i]-1'b1;
                    default:;
                endcase
            end
        end
    end
endmodule
