`timescale 1ns/1ps
module mesh_ni_write_window_tb #(parameter int WRITE_DEPTH=8);
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0;
    rv_if #(.DATA_WIDTH(128)) wr[2](),wp[2](),rd[2](),rp[2]();
    rv_if #(.DATA_WIDTH(128)) tw[2](),tb[2](),tr[2](),tp[2]();
    rv_if #(.DATA_WIDTH(128)) copy_rd[2](),copy_wr[2](),copy_rp[2](),copy_wp[2]();
    rv_if #(.DATA_WIDTH(133)) qt[2](),qr[2](),bt[2](),br[2]();
    logic [1:0] busy,done,fault;
    for(genvar n=0;n<2;n++) begin : nodes
        mesh_ni #(.X(n),.WRITE_DEPTH(WRITE_DEPTH)) ni(.clk(clk),.rst_n(rst_n),
            .write_req(wr[n]),.write_rsp(wp[n]),.read_req(rd[n]),.read_rsp(rp[n]),
            .target_write_req(tw[n]),.target_write_rsp(tb[n]),.target_read_req(tr[n]),.target_read_rsp(tp[n]),
            .req_tx(qt[n]),.req_rx(qr[n]),.rsp_tx(bt[n]),.rsp_rx(br[n]));
        vector_tile #(.WORDS_PER_BANK(32),.WRITE_DEPTH(WRITE_DEPTH)) tile(.clk(clk),.rst_n(rst_n),
            .launch(1'b0),.launch_pc(32'b0),.write_req(tw[n]),.write_rsp(tb[n]),.read_req(tr[n]),.read_rsp(tp[n]),
            .copy_read_req(copy_rd[n]),.copy_write_req(copy_wr[n]),.copy_read_rsp(copy_rp[n]),.copy_write_rsp(copy_wp[n]),
            .busy(busy[n]),.done(done[n]),.fault(fault[n]));
        assign copy_rd[n].ready=0; assign copy_wr[n].ready=0;
        assign copy_rp[n].valid=0; assign copy_rp[n].addr=0; assign copy_rp[n].data=0; assign copy_rp[n].tag=0; assign copy_rp[n].epoch=0;
        assign copy_wp[n].valid=0; assign copy_wp[n].addr=0; assign copy_wp[n].data=0; assign copy_wp[n].tag=0; assign copy_wp[n].epoch=0;
    end
    mesh_xy #(.WIDTH(2),.HEIGHT(1)) request_mesh(.clk(clk),.rst_n(rst_n),.in_ch(qt),.out_ch(qr));
    mesh_xy #(.WIDTH(2),.HEIGHT(1)) response_mesh(.clk(clk),.rst_n(rst_n),.in_ch(bt),.out_ch(br));
    logic both_start=0;
    int both_acks[2]='{0,0};
    logic [1:0] both_done=0;
    for(genvar p=0;p<2;p++) begin : concurrent_sources
        localparam logic [31:0] BASE=p==0 ? 32'h40000100 : 32'h400c0100;
        initial begin
            wait(both_start);
            for(int i=0;i<16;i++) begin
                @(negedge clk); wr[p].valid=1; wr[p].addr=BASE+32'(i*16);
                wr[p].data=128'(3000+p*1000+i); wr[p].tag=7; wr[p].epoch=9;
                do @(posedge clk); while(!wr[p].ready);
            end
            @(negedge clk); wr[p].valid=0; both_done[p]=1;
        end
        always @(posedge clk) if(rst_n && both_start && wp[p].valid && wp[p].ready) begin
            assert(wp[p].addr==BASE+32'(both_acks[p]*16) && wp[p].tag==7 && wp[p].epoch==9 && wp[p].data==0)
                else $fatal(1,"multi-source ACK owner/namespace mismatch source=%0d",p);
            both_acks[p]++;
        end
    end
    int accepted=0,acks=0,cycle=0,max_pending=0;
    int injected_run=0,max_injected_run=0,last_injected=-1;
    int target_run=0,max_target_run=0,last_target=-1;
    int accepted_before_ack=0;
    logic stream=0;
    logic [167:0] stalled_payload;
    logic was_stalled=0;
    function automatic logic [31:0] addr(input int i);
        if(i==20) return 32'h40000001; // early decode error overtakes older physical writes internally
        return 32'h40000000+32'(i*16);
    endfunction
    always @(posedge clk) begin
        cycle<=cycle+1;
        if(rst_n && stream) begin
            if(wr[0].valid && wr[0].ready) accepted++;
            if(wp[0].valid && wp[0].ready) begin
                assert(wp[0].addr==addr(acks) && wp[0].tag==5 && wp[0].epoch==4'(acks/8) && wp[0].data==(acks==20 ? 128'd1 : 128'd0))
                    else $fatal(1,"window ACK mismatch index=%0d addr=%h",acks,wp[0].addr);
                acks++;
            end
            if(accepted-acks>max_pending) max_pending=accepted-acks;
            assert(accepted-acks<=WRITE_DEPTH) else $fatal(1,"write credit overflow");
            if(was_stalled) assert(wp[0].valid && {wp[0].addr,wp[0].data,wp[0].tag,wp[0].epoch}==stalled_payload)
                else $fatal(1,"stalled client ACK changed");
            was_stalled=wp[0].valid && !wp[0].ready;
            stalled_payload={wp[0].addr,wp[0].data,wp[0].tag,wp[0].epoch};
            if(qt[0].valid && qt[0].ready && qt[0].data[132]) begin
                injected_run=cycle==last_injected+1 ? injected_run+1 : 1;
                last_injected=cycle;
                if(injected_run>max_injected_run) max_injected_run=injected_run;
            end
            if(tw[1].valid && tw[1].ready && tw[1].addr<32'h40000) begin
                target_run=cycle==last_target+1 ? target_run+1 : 1;
                last_target=cycle;
                if(target_run>max_target_run) max_target_run=target_run;
            end
        end
    end
    task automatic read_back(input logic [31:0] address, input logic [127:0] expected);
        @(negedge clk); rd[0].valid=1; rd[0].addr=address; rd[0].tag=9; rd[0].epoch=4; rp[0].ready=0;
        do @(posedge clk); while(!rd[0].ready);
        @(negedge clk); rd[0].valid=0;
        wait(rp[0].valid);
        assert(rp[0].addr==address && rp[0].data==expected && rp[0].tag==9 && rp[0].epoch==4)
            else $fatal(1,"committed memory readback mismatch address=%h",address);
        rp[0].ready=1;
        @(posedge clk); @(negedge clk); rp[0].ready=0;
    endtask
    logic producer_done=0;
    initial begin
        wait(stream);
        for(int i=0;i<64;i++) begin
            @(negedge clk); wr[0].valid=1; wr[0].addr=addr(i); wr[0].data=128'(1000+i);
            wr[0].tag=5; wr[0].epoch=4'(i/8);
            do @(posedge clk); while(!wr[0].ready);
        end
        @(negedge clk); wr[0].valid=0; producer_done=1;
    end
    initial begin
        wr[0].valid=0; wr[0].addr=0; wr[0].data=0; wr[0].tag=0; wr[0].epoch=0; wp[0].ready=0;
        rd[0].valid=0; rd[0].addr=0; rd[0].data=0; rd[0].tag=0; rd[0].epoch=0; rp[0].ready=0;
        wr[1].valid=0; wr[1].addr=0; wr[1].data=0; wr[1].tag=0; wr[1].epoch=0; wp[1].ready=1;
        rd[1].valid=0; rd[1].addr=0; rd[1].data=0; rd[1].tag=0; rd[1].epoch=0; rp[1].ready=1;
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1; stream=1;
        wait(accepted==WRITE_DEPTH);
        repeat(45) @(negedge clk);
        assert(accepted==WRITE_DEPTH && acks==0) else $fatal(1,"window/backpressure reservation failed");
        accepted_before_ack=accepted;
        wp[0].ready=1;
        while(acks<64) begin
            @(negedge clk);
            wp[0].ready=(cycle%5!=0 && cycle%11!=0);
        end
        wait(producer_done);
        @(negedge clk); stream=0; wp[0].ready=1;
        assert(max_pending==WRITE_DEPTH && accepted_before_ack==WRITE_DEPTH && max_injected_run>=WRITE_DEPTH)
            else $fatal(1,"window/injection did not pipeline depth=%0d run=%0d",WRITE_DEPTH,max_injected_run);
        if(WRITE_DEPTH>=8) assert(max_target_run>=4) else $fatal(1,"target write path still serialized run=%0d",max_target_run);
        for(int i=0;i<64;i++) if(i!=20) read_back(addr(i),128'(1000+i));
        assert(fault[1]) else $fatal(1,"rejected-write fault missing");
        // A destination change cannot bypass earlier unconsumed write ACKs.
        @(negedge clk); wp[0].ready=0; wr[0].valid=1; wr[0].addr=32'h40000300; wr[0].data=77; wr[0].tag=6; wr[0].epoch=2;
        do @(posedge clk); while(!wr[0].ready);
        @(negedge clk); wr[0].addr=32'h300; wr[0].data=88;
        wait(wp[0].valid);
        repeat(8) begin @(negedge clk); assert(!wr[0].ready) else $fatal(1,"destination fence broken"); end
        wp[0].ready=1;
        @(posedge clk);
        do @(posedge clk); while(!wr[0].ready);
        @(negedge clk); wr[0].valid=0;
        wait(wp[0].valid);
        assert(wp[0].addr==32'h300) else $fatal(1,"destination switch ACK mismatch");
        @(posedge clk); @(negedge clk);
        both_start=1;
        wait(both_done=='1 && both_acks[0]==16 && both_acks[1]==16);
        @(negedge clk); both_start=0;
        for(int i=0;i<16;i++) begin
            read_back(32'h40000100+32'(i*16),128'(3000+i));
            read_back(32'h400c0100+32'(i*16),128'(4000+i));
        end
        $display("PASS two simultaneous sources to one endpoint with overlapping network IDs");
        $display("PASS NI depth=%0d: %0d outstanding, injected run=%0d, target run=%0d, 64 ACKs, errors/readback/destination fence",WRITE_DEPTH,max_pending,max_injected_run,max_target_run);
        $finish;
    end
    initial begin #1000000; $fatal(1,"window timeout accepted=%0d acked=%0d",accepted,acks); end
endmodule
