`timescale 1ns/1ps
module rigel_mesh_system_tb;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0;
    logic [15:0] busy,done,fault;
    rv_if #(.DATA_WIDTH(128)) rd(),wr(),rp(),wp();
    rigel_mesh_top #(.WORDS_PER_BANK(32)) dut(
        .clk(clk),
        .rst_n(rst_n),
        .busy(busy),
        .done(done),
        .fault(fault),
        .host_read_req_valid(rd.valid),
        .host_read_req_ready(rd.ready),
        .host_read_req_addr(rd.addr),
        .host_read_req_tag(rd.tag),
        .host_read_req_epoch(rd.epoch),
        .host_write_req_valid(wr.valid),
        .host_write_req_ready(wr.ready),
        .host_write_req_addr(wr.addr),
        .host_write_req_data(wr.data),
        .host_write_req_tag(wr.tag),
        .host_write_req_epoch(wr.epoch),
        .host_read_rsp_valid(rp.valid),
        .host_read_rsp_ready(rp.ready),
        .host_read_rsp_addr(rp.addr),
        .host_read_rsp_data(rp.data),
        .host_read_rsp_tag(rp.tag),
        .host_read_rsp_epoch(rp.epoch),
        .host_write_rsp_valid(wp.valid),
        .host_write_rsp_ready(wp.ready),
        .host_write_rsp_addr(wp.addr),
        .host_write_rsp_data(wp.data),
        .host_write_rsp_tag(wp.tag),
        .host_write_rsp_epoch(wp.epoch));
    function automatic logic [31:0] address(input int tile, input logic [27:0] offset);
        return {2'(tile%4),2'(tile/4),offset};
    endfunction
    function automatic logic [127:0] lanes(input int value);
        logic [127:0] result;
        for(int i=0;i<16;i++) result[8*i+:8]=8'(value);
        return result;
    endfunction
    function automatic logic [31:0] enc(input int op,rs0,rs1,imm);
        return (32'(op)<<27)|(32'(rs0)<<16)|(32'(rs1)<<11)|32'(imm);
    endfunction
    int serial=0;
    logic bulk_start=0, bulk_producer_done=0;
    int bulk_accepted=0, bulk_acked=0, bulk_max_pending=0;
    int bulk_cycle=0, bulk_last_target=-1, bulk_target_run=0, bulk_max_target_run=0;
    always @(posedge clk) begin
        bulk_cycle++;
        if(rst_n && bulk_start) begin
            if(wr.valid && wr.ready) bulk_accepted++;
            if(wp.valid && wp.ready) begin
                assert(wp.addr==address(15,28'(bulk_acked*16)) && wp.tag==9 &&
                       wp.epoch==4'(bulk_acked/8) && wp.data==0)
                    else $fatal(1,"host streaming ACK/owner mismatch %0d",bulk_acked);
                bulk_acked++;
            end
            if(bulk_accepted-bulk_acked>bulk_max_pending) bulk_max_pending=bulk_accepted-bulk_acked;
            if(dut.system_core.tiles[15].tile.core.aw[0].valid && dut.system_core.tiles[15].tile.core.aw[0].ready) begin
                bulk_target_run=bulk_cycle==bulk_last_target+1 ? bulk_target_run+1 : 1;
                bulk_last_target=bulk_cycle;
                if(bulk_target_run>bulk_max_target_run) bulk_max_target_run=bulk_target_run;
            end
        end
    end
    initial begin
        wait(bulk_start);
        for(int i=0;i<64;i++) begin
            @(negedge clk); wr.valid=1; wr.addr=address(15,28'(i*16));
            wr.data=128'(1000+i); wr.tag=9; wr.epoch=4'(i/8);
            do @(posedge clk); while(!wr.ready);
        end
        @(negedge clk); wr.valid=0; bulk_producer_done=1;
    end
    task automatic write(input logic [31:0] addr, input logic [127:0] data,
                         input logic [127:0] status=0);
        @(negedge clk);
        wr.valid=1; wr.addr=addr; wr.data=data; wr.tag=4'(serial); wr.epoch=5;
        wp.ready=0;
        do @(posedge clk); while(!wr.ready);
        @(negedge clk); wr.valid=0; wr.data='1;
        wait(wp.valid);
        repeat(3) begin
            @(negedge clk);
            assert(wp.valid && wp.addr==addr && wp.data==status && wp.tag==4'(serial) && wp.epoch==5)
                else $fatal(1,"write response mismatch addr=%h data=%h expected=%h",addr,wp.data,status);
        end
        wp.ready=1;
        @(posedge clk); @(negedge clk); wp.ready=0;
        serial++;
    endtask
    task automatic read(input logic [31:0] addr, output logic [127:0] data);
        @(negedge clk);
        rd.valid=1; rd.addr=addr; rd.data=0; rd.tag=4'(serial); rd.epoch=6; rp.ready=0;
        do @(posedge clk); while(!rd.ready);
        @(negedge clk); rd.valid=0;
        wait(rp.valid);
        data=rp.data;
        repeat(3) begin
            @(negedge clk);
            assert(rp.valid && rp.addr==addr && rp.data==data && rp.tag==4'(serial) && rp.epoch==6)
                else $fatal(1,"read response unstable addr=%h",addr);
        end
        rp.ready=1;
        @(posedge clk); @(negedge clk); rp.ready=0;
        serial++;
    endtask
    logic [127:0] data;
    logic [15:0] seen_busy;
    initial begin
        rd.valid=0; rd.addr=0; rd.data=0; rd.tag=0; rd.epoch=0; rp.ready=0;
        wr.valid=0; wr.addr=0; wr.data=0; wr.tag=0; wr.epoch=0; wp.ready=0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;
        for(int n=0;n<16;n++) begin
            for(int beat=0;beat<4;beat++) begin
                write(address(n,28'(beat*16)),lanes(1));
                write(address(n,28'(128+beat*16)),lanes(n+2));
                write(address(n,28'(32'hc0000+beat*16)),lanes(3));
            end
            write(address(n,28'h40020),128'(enc(11,1,2,0)));
            write(address(n,28'h40024),128'(enc(11,3,2,1)));
            write(address(n,28'h40028),128'(enc(11,6,2,2)));
            write(address(n,28'h4002c),128'(enc(13,4,5,0)));
            write(address(n,28'h40030),128'(enc(12,0,0,0)));
            write(address(n,28'h40034),128'(enc(12,0,0,1)));
            write(address(n,28'h40038),128'(enc(12,0,0,2)));
            write(address(n,28'h4003c),128'(enc(14,0,0,0)));
            write(address(n,28'h80004),0);
            write(address(n,28'h80008),64);
            write(address(n,28'h8000c),128);
            write(address(n,28'h80010),24);
            write(address(n,28'h80014),4);
            write(address(n,28'h80018),0);
            write(address(n,28'h80040),256);
            write(address(n,28'h80044),16);
        end
        $display("Loaded all 16 tiles");
        write(32'h0ff00010,128'hffff);
        write(32'h0ff00014,32);
        write(32'h0ff00018,1);
        seen_busy=busy;
        while(done!=16'hffff) begin @(negedge clk); seen_busy |= busy; end
        assert(seen_busy==16'hffff && fault==0) else $fatal(1,"tile launch/fault masks %h/%h",seen_busy,fault);
        // DONE must imply all result memory writes have physically committed.
        for(int n=0;n<16;n++) for(int beat=0;beat<4;beat++) begin
            read(address(n,28'(32'hc0100+beat*16)),data);
            assert(data==lanes(1+(n+2)*3)) else $fatal(1,"tile %0d beat %0d FMA mismatch %h",n,beat,data);
        end
        read(32'h0ff0001c,data);
        assert(data==1) else $fatal(1,"system completion missing");
        $display("PASS all 16 tiles execute and return committed FMA results");
        // All tiles copy their result to their successor, creating contention
        // and traffic in all directions; tile 0 shares its source with host.
        for(int n=0;n<16;n++) begin
            write(address(n,28'h100010),128'(address(n,28'hc0100)));
            write(address(n,28'h100014),128'(address((n+1)%16,28'h200)));
            write(address(n,28'h100018),64);
        end
        for(int n=0;n<16;n++) write(address(n,28'h10001c),1);
        for(int n=0;n<16;n++) begin
            do read(address(n,28'h100000),data); while(!data[4]);
            assert(!data[5]) else $fatal(1,"copy fault tile %0d",n);
        end
        for(int n=0;n<16;n++) for(int beat=0;beat<4;beat++) begin
            read(address((n+1)%16,28'(32'h200+beat*16)),data);
            assert(data==lanes(1+(n+2)*3)) else $fatal(1,"copy mismatch from tile %0d",n);
        end
        assert(fault==0) else $fatal(1,"system fault %h",fault);
        $display("PASS inter-tile copies and gateway arbitration under contention");
        // Tile 1 consumes the result copied from tile 0, exercising a dependent
        // second layer and repeated partial-mask launch (old DONE bits exist).
        write(address(1,28'h80004),512);
        write(address(1,28'h80040),384);
        write(32'h0ff00010,2);
        write(32'h0ff00018,1);
        wait(busy[1]);
        wait(!busy[1] && done[1]);
        for(int beat=0;beat<4;beat++) begin
            read(address(1,28'(32'hc0180+beat*16)),data);
            assert(data==lanes(16)) else $fatal(1,"dependent tile computation mismatch");
        end
        read(32'h0ff0001c,data);
        assert(data==1 && fault==0) else $fatal(1,"repeated masked launch failed");
        // Zero-length copy completes without issuing a network transaction.
        write(address(0,28'h100018),0);
        write(address(0,28'h10001c),1);
        read(address(0,28'h100000),data);
        assert(data[4] && !data[3] && !data[5]) else $fatal(1,"zero-length copy failed");
        $display("PASS dependent tile execution, repeated mask launch, zero-length copy");
        // Invalid endpoint write must return an error rather than hang.
        write(address(15,28'h200000),0,1);
        repeat(4) @(negedge clk);
        assert(fault[15]) else $fatal(1,"invalid-write fault missing");
        // Synchronous global reset clears control/in-flight state (not RAM).
        @(negedge clk); rst_n=0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;
        repeat(4) @(negedge clk);
        assert(busy==0 && done==0 && fault==0 && !rp.valid && !wp.valid)
            else $fatal(1,"reset state mismatch");
        write(address(15,28'h300),lanes(77));
        read(address(15,28'h300),data);
        assert(data==lanes(77)) else $fatal(1,"post-reset transaction failed");
        $display("PASS system error response/reset recovery");
        // Host data path and tile-0 copy source share a multi-write owner FIFO.
        // Launch the copy just before the stream so host/copy arbitration and
        // cross-destination fences are exercised with host response stalls.
        write(address(0,28'h300),lanes(77));
        write(address(0,28'h100010),128'(address(0,28'h300)));
        write(address(0,28'h100014),128'(address(14,28'h300)));
        write(address(0,28'h100018),16);
        write(address(0,28'h10001c),1);
        @(negedge clk); bulk_start=1; wp.ready=0;
        wait(bulk_accepted>=8);
        repeat(50) @(negedge clk);
        assert(bulk_acked==0) else $fatal(1,"host ACK stalled consumer was bypassed");
        wp.ready=1;
        while(bulk_acked<64) begin @(negedge clk); wp.ready=(bulk_cycle%5!=0); end
        wait(bulk_producer_done);
        @(negedge clk); bulk_start=0; wp.ready=0;
        assert(bulk_max_pending>=8 && bulk_max_target_run>=4)
            else $fatal(1,"host/target path serialized pending=%0d run=%0d",bulk_max_pending,bulk_max_target_run);
        for(int i=0;i<64;i++) begin
            read(address(15,28'(i*16)),data);
            assert(data==128'(1000+i)) else $fatal(1,"host stream readback mismatch %0d",i);
        end
        do read(address(0,28'h100000),data); while(!data[4]);
        assert(!data[5]) else $fatal(1,"copy failed during host stream");
        read(address(14,28'h300),data);
        assert(data==lanes(77) && fault==0) else $fatal(1,"host/copy response owner or data corruption");
        $display("PASS host pipeline: 64 writes, pending=%0d, target run=%0d, concurrent copy/ACK ownership",bulk_max_pending,bulk_max_target_run);
        $finish;
    end
    initial begin #10000000; $fatal(1,"system timeout busy=%h done=%h fault=%h",busy,done,fault); end
endmodule
