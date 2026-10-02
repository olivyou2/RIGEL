`timescale 1ns/1ps
module mesh_task_scheduler_tb;
    logic clk=0; always #5 clk=~clk;
    logic rst_n=0;
    logic task_valid=0, task_ready, task_has_dependency=0, task_has_copy=0, task_copy_only=0, submit_error;
    logic [7:0] task_id=0,task_dependency=0;
    logic [3:0] task_tile=0;
    logic [31:0] task_pc=0,task_src=32'h1000,task_dst=32'h2000,task_bytes=32'd16;
    logic [15:0] tile_busy=0,tile_done=0,tile_fault=0,reserved,launch;
    logic [3:0] copy_tile;
    logic [31:0] launch_pc,copy_src,copy_dst,copy_bytes;
    logic copy_valid,copy_ready=0,copy_done=0,copy_error=0;
    logic completion_valid,completion_ready=0,completion_error;
    logic [7:0] completion_id;
    logic [3:0] completion_tile;
    logic [255:0] completed,failed;
    mesh_task_scheduler #(.QUEUE_DEPTH(2)) dut(.*);
    int remaining[16]; int starts[16]; int cycles=0, completions=0, errors=0;
    logic [255:0] seen=0;
    always @(posedge clk) if(rst_n) begin
        cycles<=cycles+1;
        for(int t=0;t<16;t++) begin
            if(launch[t]) begin
                assert(!tile_busy[t] && reserved[t]) else $fatal(1,"tile reservation");
                if(t==1) assert(completed[1]) else $fatal(1,"dependency started early");
                if(t==2) assert(copy_done_seen) else $fatal(1,"copy started early");
                starts[t]<=starts[t]+1; tile_busy[t]<=1; tile_done[t]<=0; remaining[t]<=8+t;
            end else if(tile_busy[t]) begin
                remaining[t]<=remaining[t]-1;
                if(remaining[t]==1) begin tile_busy[t]<=0; tile_done[t]<=1; end
            end
        end
        if(completion_valid && completion_ready) begin
            assert(!seen[completion_id]) else $fatal(1,"duplicate completion");
            seen[completion_id]<=1; completions<=completions+1;
            if(completion_error) errors<=errors+1;
        end
    end
    logic copy_done_seen=0;
    task automatic submit(input int id, tile, dep, input bit copy, input bit copy_only=0);
        @(negedge clk); task_valid=1; task_id=8'(id); task_tile=4'(tile);
        task_has_dependency=dep>=0; task_dependency=8'(dep); task_has_copy=copy; task_copy_only=copy_only; task_pc=32'(id*4);
        do @(posedge clk); while(!task_ready);
        @(negedge clk); task_valid=0;
    endtask
    initial begin
        for(int t=0;t<16;t++) begin remaining[t]=0; starts[t]=0; end
        repeat(4) @(negedge clk); rst_n=1;
        submit(1,0,-1,0); submit(2,1,1,0); submit(3,0,-1,0);
        submit(4,2,-1,1); submit(5,3,-1,0);
        wait(copy_valid); repeat(8) begin @(posedge clk); assert(copy_valid && copy_src==32'h1000 && copy_bytes==16); end
        @(negedge clk); copy_ready=1; @(negedge clk); copy_ready=0;
        repeat(10) @(negedge clk); assert(starts[2]==0 && starts[3]==1); copy_done=1; copy_done_seen=1;
        @(negedge clk); copy_done=0;
        wait(completion_valid); repeat(10) @(negedge clk);
        assert(reserved[completion_tile] && !completed[completion_id]);
        completion_ready=1;
        wait(completions==5);
        assert(starts[0]==2 && starts[1]==1 && starts[2]==1 && starts[3]==1);
        // Copy error, dependent failure propagation, and continued independent work.
        submit(6,4,-1,1); submit(7,5,6,0); submit(8,6,-1,0);
        wait(copy_valid); @(negedge clk); copy_ready=1; @(negedge clk); copy_ready=0;
        repeat(3) @(negedge clk); copy_done=1; copy_error=1;
        @(negedge clk); copy_done=0; copy_error=0;
        wait(completions==8); @(negedge clk);
        assert(failed[6] && failed[7] && completed[8] && starts[4]==0 && starts[5]==0 && errors==2);
        submit(13,8,-1,1,1);
        wait(copy_valid); @(negedge clk); copy_ready=1; @(negedge clk); copy_ready=0;
        repeat(3) @(negedge clk); copy_done=1; @(negedge clk); copy_done=0;
        wait(completions==9); @(negedge clk);
        assert(completed[13] && starts[8]==0) else $fatal(1,"copy-only launched a core");
        tile_fault[9]=1; submit(14,9,-1,0);
        wait(completions==10); @(negedge clk);
        assert(failed[14] && starts[9]==0) else $fatal(1,"faulted tile launched");
        submit(1,0,-1,0); assert(submit_error) else $fatal(1,"duplicate accepted");
        submit(9,0,99,0); assert(submit_error) else $fatal(1,"unknown dependency accepted");
        // Backpressure at full per-tile FIFO while external owner is busy.
        tile_busy[7]=1; remaining[7]=1000;
        submit(10,7,-1,0); submit(11,7,-1,0);
        @(negedge clk); task_tile=7; task_valid=1; task_id=12; task_has_dependency=0;
        repeat(4) begin @(posedge clk); assert(!task_ready); end
        @(negedge clk); task_valid=0; rst_n=0;
        repeat(3) @(negedge clk);
        assert(reserved==0 && completed==0 && failed==0 && !copy_valid && !completion_valid);
        $display("PASS scheduler: dependencies, per-tile order/reservation, copy stalls/errors, completion stalls, rejection/full/reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
