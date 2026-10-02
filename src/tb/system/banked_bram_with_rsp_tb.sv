`timescale 1ns/1ps
module banked_bram_with_rsp_tb;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0;
    rv_if #(.DATA_WIDTH(128)) rd[2](), rp[2](), wr[2](), wp[2]();
    banked_bram_with_rsp #(.READ_PORTS(2),.WRITE_PORTS(2),.WORDS_PER_BANK(32)) dut(
        .clk(clk),.rst_n(rst_n),.read_req(rd),.read_rsp(rp),.write_req(wr),.write_rsp(wp));
    int sent[2], acked[2], cycles=0;
    logic [1:0] fired;
    always @(posedge clk) cycles<=cycles+1;
    for(genvar p=0;p<2;p++) begin : writers
        assign wp[p].ready=rst_n && cycles>40 && (cycles+p)%5!=0;
        always @(negedge clk) begin
            if(!rst_n) begin wr[p].valid=0; wr[p].addr=0; wr[p].data=0; wr[p].tag=0; wr[p].epoch=0; end
            else if((!wr[p].valid || fired[p]) && sent[p]<32) begin
                wr[p].valid=1; wr[p].addr=32'(p*512+sent[p]*16);
                wr[p].data=128'(1000*p+sent[p]); wr[p].tag=4'(sent[p]); wr[p].epoch=4'(p+1);
            end else if(fired[p]) wr[p].valid=0;
        end
        always @(posedge clk) begin
            if(!rst_n) begin sent[p]<=0; acked[p]<=0; fired[p]<=0; end
            else begin
                fired[p]<=wr[p].valid && wr[p].ready;
                if(wr[p].valid && wr[p].ready) sent[p]<=sent[p]+1;
                if(wp[p].valid && wp[p].ready) begin
                    assert(wp[p].addr==32'(p*512+acked[p]*16) && wp[p].tag==4'(acked[p]) &&
                           wp[p].epoch==4'(p+1) && wp[p].data==0 && acked[p]<sent[p])
                        else $fatal(1,"BRAM ACK identity/order mismatch");
                    acked[p]<=acked[p]+1;
                end
            end
        end
    end
    task automatic check(input int word);
        @(negedge clk);
        rd[0].addr=32'(word*16); rd[1].addr=32'(512+word*16);
        rd[0].valid=1; rd[1].valid=1;
        // Both independent banks/clients are empty at this point.
        do @(posedge clk); while(!rd[0].ready || !rd[1].ready);
        @(negedge clk); rd[0].valid=0; rd[1].valid=0;
        wait(rp[0].valid && rp[1].valid);
        assert(rp[0].data==128'(word) && rp[1].data==128'(1000+word))
            else $fatal(1,"ACK before memory visibility / bad data");
        rp[0].ready=1; rp[1].ready=1;
        @(posedge clk); @(negedge clk); rp[0].ready=0; rp[1].ready=0;
    endtask
    initial begin
        rd[0].valid=0; rd[0].addr=0; rd[0].data=0; rd[0].tag=0; rd[0].epoch=0; rp[0].ready=0;
        rd[1].valid=0; rd[1].addr=0; rd[1].data=0; rd[1].tag=0; rd[1].epoch=0; rp[1].ready=0;
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        wait(acked[0]==32 && acked[1]==32);
        for(int word=0;word<32;word++) check(word);
        $display("PASS BRAM completion reservations, ACK stalls/order, committed data visibility");
        $finish;
    end
    initial begin #1000000; $fatal(1,"BRAM ACK timeout"); end
endmodule
