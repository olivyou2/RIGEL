`timescale 1ns/1ps
module dma_mesh_write_tb;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0, accept_target=0;
    int reads=0, commits=0;
    rv_if #(.DATA_WIDTH(128)) rd(), data_rsp();
    rv_if #(.DATA_WIDTH(128)) wr[2](), ack[2](), target[2]();
    rv_if #(.DATA_WIDTH(130)) req_tx[2](), req_rx[2](), rsp_tx[2](), rsp_rx[2]();
    dma_ctrl_if ctrl();
    dma_with_write_rsp dma_dut(.clk(clk), .rst_n(rst_n), .read_req(rd), .read_rsp(data_rsp),
        .write_req(wr[0]), .write_rsp(ack[0]), .ctrl(ctrl));
    assign wr[1].valid=0;
    assign wr[1].addr=0;
    assign wr[1].data=0;
    assign wr[1].tag=0;
    assign wr[1].epoch=0;
    assign ack[1].ready=1;
    assign target[0].ready=1;
    assign target[1].ready=accept_target;
    assign rd.ready=rst_n && !data_rsp.valid;
    for(genvar i=0; i<2; i++) begin : nodes
        mesh_write_ni #(.X_BITS(1), .Y_BITS(1), .X(1'(i))) ni (
            .clk(clk), .rst_n(rst_n), .write_req(wr[i]), .write_rsp(ack[i]),
            .target_write_req(target[i]), .mesh_req_tx(req_tx[i]), .mesh_req_rx(req_rx[i]),
            .mesh_rsp_tx(rsp_tx[i]), .mesh_rsp_rx(rsp_rx[i])
        );
    end
    mesh #(.DATA_WIDTH(130), .MESH_W(2), .MESH_H(1), .X_BITS(1), .Y_BITS(1)) requests (
        .clk(clk), .rst_n(rst_n), .in_ch(req_tx), .out_ch(req_rx));
    mesh #(.DATA_WIDTH(130), .MESH_W(2), .MESH_H(1), .X_BITS(1), .Y_BITS(1)) responses (
        .clk(clk), .rst_n(rst_n), .in_ch(rsp_tx), .out_ch(rsp_rx));
    always @(posedge clk) begin
        if(!rst_n) begin
            data_rsp.valid<=0; data_rsp.addr<=0; data_rsp.data<=0;
            data_rsp.tag<=0; data_rsp.epoch<=0; reads<=0; commits<=0;
        end else begin
            if(data_rsp.valid && data_rsp.ready) data_rsp.valid<=0;
            if(rd.valid && rd.ready) begin
                data_rsp.valid<=1; data_rsp.addr<=rd.addr; data_rsp.data<=128'(rd.addr);
                data_rsp.tag<=4'(reads); data_rsp.epoch<=7; reads<=reads+1;
            end
            if(target[1].valid && target[1].ready) begin
                assert(target[1].addr==32'h120+32'(commits*16) &&
                       target[1].data==128'(32'h200+commits*16) &&
                       target[1].tag==4'(commits) && target[1].epoch==7)
                    else $fatal(1,"remote DMA write mismatch");
                commits<=commits+1;
            end
            if(ctrl.ready && reads!=0)
                assert(commits==3) else $fatal(1,"DMA ready before remote commits");
        end
    end
    initial begin
        ctrl.valid=0; ctrl.addr_src=32'h200; ctrl.addr_dst=32'h80000120;
        ctrl.step=16; ctrl.length=48;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1; ctrl.valid=1;
        do @(posedge clk); while(!ctrl.ready);
        @(negedge clk); ctrl.valid=0;
        wait(target[1].valid);
        repeat(20) @(negedge clk);
        assert(!ctrl.ready && commits==0) else $fatal(1,"DMA finished during target stall");
        accept_target=1;
        wait(commits==3);
        assert(!ctrl.ready) else $fatal(1,"DMA did not wait for returning ACK");
        wait(ctrl.ready);
        assert(reads==3 && commits==3) else $fatal(1,"DMA count mismatch");
        $display("PASS end-to-end DMA -> NI -> mesh -> remote endpoint -> ACK -> DMA completion");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
