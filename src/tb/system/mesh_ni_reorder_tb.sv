`timescale 1ns/1ps
module mesh_ni_reorder_tb;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0;
    rv_if #(.DATA_WIDTH(128)) wr(),wp(),rd(),rp(),tw(),tb(),tr(),tp();
    rv_if #(.DATA_WIDTH(133)) qt(),qr(),bt(),br();
    mesh_ni dut(.clk(clk),.rst_n(rst_n),.write_req(wr),.write_rsp(wp),.read_req(rd),.read_rsp(rp),
        .target_write_req(tw),.target_write_rsp(tb),.target_read_req(tr),.target_read_rsp(tp),
        .req_tx(qt),.req_rx(qr),.rsp_tx(bt),.rsp_rx(br));
    int sent=0,retired=0;
    logic check_replies=1;
    logic [3:0] ids[8];
    always @(posedge clk) if(rst_n) begin
        if(qt.valid && qt.ready && qt.data[132] && check_replies) begin
            assert(sent<8 && qt.addr==32'h40000100+32'(sent*16) && qt.data[127:0]==128'(sent+100))
                else $fatal(1,"NI packet/order mismatch");
            ids[sent]=qt.tag; sent++;
        end
        if(wp.valid && wp.ready && check_replies) begin
            assert(wp.addr==32'h40000100+32'(retired*16) && wp.tag==9 && wp.epoch==4'(retired) && wp.data==128'(retired%2))
                else $fatal(1,"NI reordered ACK restoration failed");
            retired++;
        end
    end
    task automatic send(input int i);
        @(negedge clk); wr.valid=1; wr.addr=32'h40000100+32'(i*16);
        wr.data=128'(100+i); wr.tag=9; wr.epoch=4'(i);
        do @(posedge clk); while(!wr.ready);
        @(negedge clk); wr.valid=0;
    endtask
    task automatic ack(input int i);
        @(negedge clk); br.valid=1; br.addr=32'h100+32'(i*16);
        br.tag=ids[i]; br.epoch=4'(i); br.data={1'b1,4'b0,128'(i%2)};
        do @(posedge clk); while(!br.ready);
        @(negedge clk); br.valid=0;
    endtask
    initial begin
        wr.valid=0; wr.addr=0; wr.data=0; wr.tag=0; wr.epoch=0; wp.ready=0;
        rd.valid=0; rd.addr=32'h40000200; rd.data=0; rd.tag=12; rd.epoch=3; rp.ready=0;
        qr.valid=0; qr.addr=0; qr.data=0; qr.tag=0; qr.epoch=0;
        br.valid=0; br.addr=0; br.data=0; br.tag=0; br.epoch=0;
        qt.ready=0; bt.ready=1; tw.ready=1; tr.ready=1;
        tb.valid=0; tb.addr=0; tb.data=0; tb.tag=0; tb.epoch=0;
        tp.valid=0; tp.addr=0; tp.data=0; tp.tag=0; tp.epoch=0;
        repeat(3) @(posedge clk); @(negedge clk); rst_n=1;
        for(int i=0;i<8;i++) send(i);
        assert(!wr.ready && !wp.valid) else $fatal(1,"window did not reserve exactly 8 slots");
        repeat(5) @(negedge clk);
        qt.ready=1;
        wait(sent==8);
        for(int i=7;i>0;i--) begin
            ack(i);
            assert(!wp.valid) else $fatal(1,"later ACK escaped before head ACK");
        end
        ack(0);
        wait(wp.valid);
        @(negedge clk); rd.valid=1;
        repeat(10) begin
            @(negedge clk);
            assert(wp.valid && wp.addr==32'h40000100 && wp.tag==9 && wp.data==0 &&
                   !wr.ready && !rd.ready) else $fatal(1,"stalled ACK/window/read fence failed");
        end
        wp.ready=1;
        wait(retired==8);
        do @(posedge clk); while(!rd.ready);
        @(negedge clk); rd.valid=0;
        wait(qt.valid && !qt.data[132]);
        @(posedge clk); @(negedge clk);
        br.valid=1; br.addr=32'h200; br.tag=12; br.epoch=3; br.data={5'b0,128'hdeadbeef};
        do @(posedge clk); while(!br.ready);
        @(negedge clk); br.valid=0;
        wait(rp.valid);
        repeat(4) begin
            @(negedge clk);
            assert(rp.valid && rp.addr==32'h40000200 && rp.tag==12 && rp.epoch==3 && rp.data==128'hdeadbeef)
                else $fatal(1,"NI read recovery failed");
        end
        rp.ready=1;
        @(posedge clk); @(negedge clk); rp.ready=0;
        // Reset a queued write while network injection is stalled.
        check_replies=0; qt.ready=0;
        send(0);
        repeat(4) @(negedge clk);
        rst_n=0;
        repeat(3) @(posedge clk); @(negedge clk); rst_n=1;
        repeat(3) @(negedge clk);
        assert(!qt.valid && !wp.valid && wr.ready) else $fatal(1,"stale write after reset");
        $display("PASS NI window=8, reverse-order ACKs, duplicate client tags, read fence, stalls/reset");
        $finish;
    end
    initial begin #1000000; $fatal(1,"NI reorder timeout sent=%0d retired=%0d",sent,retired); end
endmodule
