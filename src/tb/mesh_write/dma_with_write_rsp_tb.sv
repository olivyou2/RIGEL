`timescale 1ns/1ps
module dma_with_write_rsp_tb;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0;
    rv_if #(.DATA_WIDTH(128)) rd(), data_rsp(), wr(), ack();
    dma_ctrl_if ctrl();
    dma_with_write_rsp dut(.clk(clk), .rst_n(rst_n), .read_req(rd),
        .read_rsp(data_rsp), .write_req(wr), .write_rsp(ack), .ctrl(ctrl));
    assign rd.ready = rst_n && !data_rsp.valid;
    int reads=0, writes=0;
    always @(posedge clk) begin
        if (!rst_n) begin
            data_rsp.valid<=0; data_rsp.addr<=0; data_rsp.data<=0;
            data_rsp.tag<=0; data_rsp.epoch<=0; reads<=0; writes<=0;
        end else begin
            if (data_rsp.valid && data_rsp.ready) data_rsp.valid<=0;
            if (rd.valid && rd.ready) begin
                data_rsp.valid<=1;
                data_rsp.addr<=rd.addr;
                data_rsp.data<=128'(rd.addr);
                data_rsp.tag<=4'(reads);
                data_rsp.epoch<=5;
                reads<=reads+1;
            end
            if (wr.valid && wr.ready) begin
                assert (wr.addr==32'h80000100+32'(writes*16) &&
                        wr.data==128'(32'h200+writes*16) && wr.tag==4'(writes) && wr.epoch==5)
                    else $fatal(1, "DMA write data/order mismatch");
                writes<=writes+1;
            end
        end
    end
    task automatic acknowledge(input int index);
        @(negedge clk);
        ack.addr=32'h80000100+32'(index*16); ack.tag=4'(index); ack.epoch=5;
        ack.valid=1;
        do @(posedge clk); while (!ack.ready);
        @(negedge clk); ack.valid=0;
    endtask
    initial begin
        ctrl.valid=0; ctrl.addr_src=32'h200; ctrl.addr_dst=32'h80000100;
        ctrl.step=16; ctrl.length=32;
        wr.ready=0;
        ack.valid=0; ack.addr=0; ack.data=0; ack.tag=0; ack.epoch=0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1; ctrl.valid=1;
        do @(posedge clk); while (!ctrl.ready);
        @(negedge clk); ctrl.valid=0;
        wait(wr.valid);
        repeat(5) begin
            @(negedge clk);
            assert (wr.valid && wr.addr==32'h80000100 && wr.data==128'h200 && !ctrl.ready)
                else $fatal(1, "DMA stalled write unstable");
        end
        wr.ready=1;
        wait(writes==1);
        repeat(15) begin
            @(negedge clk);
            assert (!ctrl.ready && !wr.valid) else $fatal(1, "DMA completed/issued before ACK");
        end
        acknowledge(0);
        wait(writes==2);
        repeat(15) begin
            @(negedge clk);
            assert (!ctrl.ready) else $fatal(1, "DMA completed before final ACK");
        end
        acknowledge(1);
        wait(ctrl.ready);
        assert (reads==2 && writes==2) else $fatal(1, "DMA count mismatch");
        // No-op descriptor must not require an ACK.
        @(negedge clk); ctrl.length=0; ctrl.valid=1;
        @(posedge clk); @(negedge clk); ctrl.valid=0;
        repeat(5) @(posedge clk);
        assert (ctrl.ready && reads==2 && writes==2) else $fatal(1, "zero-length DMA stalled");
        $display("PASS ACK-aware DMA: delayed ACKs, completion, write stability, zero length");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
