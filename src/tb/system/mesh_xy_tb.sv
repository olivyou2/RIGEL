`timescale 1ns/1ps
module mesh_xy_tb;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0;
    rv_if #(.DATA_WIDTH(133)) inputs[16](), outputs[16]();
    mesh_xy dut(.clk(clk),.rst_n(rst_n),.in_ch(inputs),.out_ch(outputs));
    int sent[16], received[16];
    logic [31:0] seen[16];
    logic [15:0] finished;
    int cycle=0;
    always @(posedge clk) cycle<=cycle+1;
    for(genvar n=0;n<16;n++) begin : traffic
        // Every source sends to every destination twice, with independent
        // stalls and exact source/sequence scoreboards at every destination.
        int destination;
        logic stalled;
        logic [172:0] last_payload;
        assign outputs[n].ready=rst_n && cycle>40 && ((cycle+n)%7!=0) && ((cycle+n)%11!=0);
        always @(negedge clk) begin
            if(!rst_n) begin inputs[n].valid=0; inputs[n].addr=0; inputs[n].data=0; inputs[n].tag=0; inputs[n].epoch=0; end
            else if(!inputs[n].valid && sent[n]<32) begin
                destination=(sent[n]+n)%16;
                inputs[n].valid=1;
                inputs[n].addr={2'(destination%4),2'(destination/4),28'(sent[n]*16)};
                inputs[n].data=133'(n*32+sent[n]); inputs[n].tag=4'(n); inputs[n].epoch=4'(sent[n]/16);
            end else if(finished[n]) inputs[n].valid=0;
        end
        always @(posedge clk) begin
            if(!rst_n) begin sent[n]<=0; received[n]<=0; seen[n]<=0; finished[n]<=0; stalled<=0; last_payload<=0; end
            else begin
                if(inputs[n].valid && inputs[n].ready) begin sent[n]<=sent[n]+1; finished[n]<=1; end
                else finished[n]<=0;
                if(stalled) assert(outputs[n].valid && {outputs[n].addr,outputs[n].data,outputs[n].tag,outputs[n].epoch}==last_payload)
                    else $fatal(1,"mesh output changed while stalled");
                stalled<=outputs[n].valid && !outputs[n].ready;
                last_payload<={outputs[n].addr,outputs[n].data,outputs[n].tag,outputs[n].epoch};
                if(outputs[n].valid && outputs[n].ready) begin
                    assert(outputs[n].addr[31:30]==2'(n%4) && outputs[n].addr[29:28]==2'(n/4))
                        else $fatal(1,"misrouted packet");
                    // The pair (source, round) is unique at a destination.
                    assert(!seen[n][int'(outputs[n].tag)*2+int'(outputs[n].epoch)]) else $fatal(1,"duplicate packet");
                    assert(outputs[n].data==133'(int'(outputs[n].tag)*32+int'(outputs[n].addr[8:4])) &&
                           (int'(outputs[n].addr[8:4])+int'(outputs[n].tag))%16==n)
                        else $fatal(1,"packet corruption");
                    seen[n][int'(outputs[n].tag)*2+int'(outputs[n].epoch)]<=1;
                    received[n]<=received[n]+1;
                end
            end
        end
    end
    initial begin
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        // Reset all routers and clients together while packets are queued.
        wait(sent[0]>=4);
        @(negedge clk); rst_n=0;
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        wait(received[0]==32 && received[1]==32 && received[2]==32 && received[3]==32 &&
             received[4]==32 && received[5]==32 && received[6]==32 && received[7]==32 &&
             received[8]==32 && received[9]==32 && received[10]==32 && received[11]==32 &&
             received[12]==32 && received[13]==32 && received[14]==32 && received[15]==32);
        for(int n=0;n<16;n++) assert(sent[n]==32 && seen[n]=='1) else $fatal(1,"mesh packet loss");
        $display("PASS 4x4 XY mesh: 512 contended packets, all destinations, backpressure stability, in-flight reset");
        $finish;
    end
    initial begin #1000000; $fatal(1,"mesh timeout"); end
endmodule
