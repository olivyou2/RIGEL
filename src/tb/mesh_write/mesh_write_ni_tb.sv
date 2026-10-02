`timescale 1ns/1ps
module mesh_write_ni_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    logic accept_targets = 0;
    int commits[2];
    rv_if #(.DATA_WIDTH(128)) wr[2](), ack[2](), target[2]();
    rv_if #(.DATA_WIDTH(130)) req_tx[2](), req_rx[2](), rsp_tx[2](), rsp_rx[2]();
    for (genvar i=0; i<2; i++) begin : nodes
        mesh_write_ni #(.X_BITS(1), .Y_BITS(1), .X(1'(i))) ni (
            .clk(clk), .rst_n(rst_n), .write_req(wr[i]), .write_rsp(ack[i]),
            .target_write_req(target[i]), .mesh_req_tx(req_tx[i]),
            .mesh_req_rx(req_rx[i]), .mesh_rsp_tx(rsp_tx[i]), .mesh_rsp_rx(rsp_rx[i])
        );
        assign target[i].ready = accept_targets;
        always @(posedge clk) begin
            if (!rst_n) commits[i] <= 0;
            else if (target[i].valid && target[i].ready) begin
                assert (target[i].addr == 32'h120 && target[i].data == 128'(101-i) &&
                        target[i].tag == 4'(2+i) && target[i].epoch == 4'h5)
                    else $fatal(1, "target payload mismatch at node %0d", i);
                commits[i] <= commits[i]+1;
            end
        end
    end
    mesh #(.DATA_WIDTH(130), .MESH_W(2), .MESH_H(1), .X_BITS(1), .Y_BITS(1)) requests (
        .clk(clk), .rst_n(rst_n), .in_ch(req_tx), .out_ch(req_rx)
    );
    mesh #(.DATA_WIDTH(130), .MESH_W(2), .MESH_H(1), .X_BITS(1), .Y_BITS(1)) responses (
        .clk(clk), .rst_n(rst_n), .in_ch(rsp_tx), .out_ch(rsp_rx)
    );
    task automatic send0;
        @(negedge clk);
        wr[0].valid=1; wr[0].addr=32'h80000120; wr[0].data=100; wr[0].tag=3; wr[0].epoch=5;
        do @(posedge clk); while (!wr[0].ready);
        @(negedge clk); wr[0].valid=0; wr[0].data='1;
    endtask
    task automatic send1;
        @(negedge clk);
        wr[1].valid=1; wr[1].addr=32'h00000120; wr[1].data=101; wr[1].tag=2; wr[1].epoch=5;
        do @(posedge clk); while (!wr[1].ready);
        @(negedge clk); wr[1].valid=0; wr[1].data='1;
    endtask
    initial begin
        wr[0].valid=0; wr[0].addr=0; wr[0].data=0; wr[0].tag=0; wr[0].epoch=0;
        wr[1].valid=0; wr[1].addr=0; wr[1].data=0; wr[1].tag=0; wr[1].epoch=0;
        ack[0].ready=0; ack[1].ready=0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1;
        fork send0(); send1(); join
        repeat(20) @(posedge clk);
        assert (!ack[0].valid && !ack[1].valid && commits[0]==0 && commits[1]==0)
            else $fatal(1, "ACK before endpoint acceptance");
        @(negedge clk); accept_targets=1;
        wait (ack[0].valid && ack[1].valid);
        repeat(12) begin
            @(negedge clk);
            assert (ack[0].valid && ack[1].valid && !wr[0].ready && !wr[1].ready &&
                    ack[0].addr==32'h80000120 && ack[1].addr==32'h120 &&
                    ack[0].tag==3 && ack[1].tag==2 && ack[0].epoch==5 && ack[1].epoch==5 &&
                    ack[0].data==0 && ack[1].data==0)
                else $fatal(1, "ACK stability/ownership mismatch");
        end
        ack[0].ready=1; ack[1].ready=1;
        @(posedge clk); @(negedge clk);
        assert (!ack[0].valid && !ack[1].valid && wr[0].ready && wr[1].ready &&
                commits[0]==1 && commits[1]==1) else $fatal(1, "loss or duplication");
        // Reset with a queued, uncommitted request. No stale ACK may escape.
        accept_targets=0;
        send0();
        repeat(10) @(posedge clk);
        @(negedge clk); rst_n=0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1; accept_targets=1;
        repeat(12) @(posedge clk);
        assert (commits[0]==0 && commits[1]==0 && !ack[0].valid && !ack[1].valid)
            else $fatal(1, "stale transaction after reset");
        send0();
        wait (ack[0].valid);
        @(posedge clk); @(negedge clk);
        assert (commits[1]==1) else $fatal(1, "post-reset write failed");
        $display("PASS mesh write ACK: bidirectional routing, target stall, response stall, reset");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
