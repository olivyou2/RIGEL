`timescale 1ns/1ps
module mesh_task_control_tb;
    logic clk=0,rst_n=0; always #5 clk=~clk;
    logic [31:0] s_task_axi_awaddr=0,s_task_axi_wdata=0,s_task_axi_araddr=0,s_task_axi_rdata;
    logic [3:0] s_task_axi_wstrb=15;
    logic s_task_axi_awvalid=0,s_task_axi_wvalid=0,s_task_axi_bready=0,s_task_axi_arvalid=0,s_task_axi_rready=0;
    logic s_task_axi_awready,s_task_axi_wready,s_task_axi_bvalid,s_task_axi_arready,s_task_axi_rvalid;
    logic [1:0] s_task_axi_bresp,s_task_axi_rresp;
    logic task_valid,task_ready=0,task_has_dependency,task_has_copy,task_copy_only,submit_error=0;
    logic [7:0] task_id,task_dependency;
    logic [3:0] task_tile,host_tile;
    logic [31:0] task_pc,task_src,task_dst,task_bytes;
    logic completion_valid=0,completion_ready,completion_error=0;
    logic [7:0] completion_id=19;
    logic [3:0] completion_tile=5;
    logic [255:0] completed=256'h80000,failed=0;
    logic [15:0] busy=16'h0010,done=0,fault=0;
    mesh_task_control dut(.*);
    int drained=0;
    always @(posedge clk) if(completion_valid && completion_ready) begin completion_valid<=0; drained<=drained+1; end
    task automatic write(input int offset,value,input logic [1:0] status=0);
        // W first, then AW, with independent channel gaps.
        @(negedge clk); s_task_axi_wdata=32'(value); s_task_axi_wvalid=1;
        do @(posedge clk); while(!s_task_axi_wready);
        @(negedge clk); s_task_axi_wvalid=0;
        repeat(2) @(negedge clk); s_task_axi_awaddr=32'(offset); s_task_axi_awvalid=1;
        do @(posedge clk); while(!s_task_axi_awready);
        @(negedge clk); s_task_axi_awvalid=0;
        wait(s_task_axi_bvalid);
        repeat(3) begin @(negedge clk); assert(s_task_axi_bvalid && s_task_axi_bresp==status); end
        s_task_axi_bready=1; @(negedge clk); s_task_axi_bready=0;
    endtask
    task automatic read(input int offset,value,input logic [1:0] status=0,input bit completion=0);
        @(negedge clk); s_task_axi_araddr=32'(offset); s_task_axi_arvalid=1;
        do @(posedge clk); while(!s_task_axi_arready);
        @(negedge clk); s_task_axi_arvalid=0;
        wait(s_task_axi_rvalid);
        repeat(4) begin @(negedge clk);
            assert(s_task_axi_rvalid && s_task_axi_rdata==32'(value) && s_task_axi_rresp==status);
            if(completion) assert(completion_valid && drained==0 && !completion_ready);
        end
        s_task_axi_rready=1; @(negedge clk); s_task_axi_rready=0;
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        write(4,'h7513); write(8,7); write(12,32); write(16,'h1000); write(20,'h80000000); write(24,64); write(28,1);
        assert(task_valid && task_id==19 && task_tile==5 && task_dependency==7 &&
            task_has_dependency && task_has_copy && task_copy_only && task_pc==32 && task_bytes==64);
        write(12,128); assert(task_pc==32); // staged next descriptor must not alter the pending snapshot
        write(28,1,2); read(0,1);
        task_ready=1; @(negedge clk); task_ready=0;
        submit_error=1; @(negedge clk); submit_error=0;
        read(0,2); write(0,2); read(0,0);
        completion_error=1; completion_valid=1;
        read(0,4); read(32,'h1513,0,1); assert(drained==1);
        read(32,0,2); read(64,'h80000); read(96,0); read(36,16);
        write(44,15); read(44,15); write(44,16,2);
        write(4,1); write(8,0); write(28,1);
        @(negedge clk); rst_n=0; repeat(3) @(negedge clk);
        assert(!task_valid && !s_task_axi_bvalid && !s_task_axi_rvalid && host_tile==0);
        $display("PASS descriptor CSR: independent AW/W, stable snapshot, submit backpressure/error, completion pop on R handshake, bitmaps and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
