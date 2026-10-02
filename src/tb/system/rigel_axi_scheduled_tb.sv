`timescale 1ns/1ps
module rigel_axi_scheduled_tb;
    logic clk=0, rst_n=0;
    logic [15:0] busy, done, fault;
    logic [31:0] s_axi_awaddr,s_axi_araddr;
    logic [7:0] s_axi_awlen,s_axi_arlen;
    logic [2:0] s_axi_awsize,s_axi_arsize;
    logic [1:0] s_axi_awburst,s_axi_arburst;
    logic [3:0] s_axi_awid,s_axi_arid;
    logic s_axi_awvalid,s_axi_wvalid,s_axi_bready,s_axi_arvalid,s_axi_rready;
    logic s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid;
    logic [127:0] s_axi_wdata;
    logic [15:0] s_axi_wstrb;
    logic s_axi_wlast;
    logic [3:0] s_axi_bid,s_axi_rid;
    logic [1:0] s_axi_bresp,s_axi_rresp;
    logic [127:0] s_axi_rdata;
    logic s_axi_rlast;
    logic [31:0] m_axi_awaddr,m_axi_wdata,m_axi_araddr;
    logic [2:0] m_axi_awprot,m_axi_arprot;
    logic [3:0] m_axi_wstrb;
    logic m_axi_awvalid,m_axi_wvalid,m_axi_bready,m_axi_arvalid,m_axi_rready;
    logic m_axi_awready,m_axi_wready,m_axi_bvalid,m_axi_arready,m_axi_rvalid;
    logic [1:0] m_axi_bresp,m_axi_rresp;
    logic [31:0] m_axi_rdata;
    logic [31:0] s_task_axi_awaddr,s_task_axi_wdata,s_task_axi_araddr;
    logic [3:0] s_task_axi_wstrb;
    logic s_task_axi_awvalid,s_task_axi_wvalid,s_task_axi_bready,s_task_axi_arvalid,s_task_axi_rready;
    logic s_task_axi_awready,s_task_axi_wready,s_task_axi_bvalid,s_task_axi_arready,s_task_axi_rvalid;
    logic [1:0] s_task_axi_bresp,s_task_axi_rresp;
    logic [31:0] s_task_axi_rdata;

    logic [255:0] completed,failed;
    logic completion_valid,completion_ready,completion_error;
    logic [7:0] completion_id;
    logic [3:0] completion_tile;
    assign completed=dut.system_core.completed;
    assign failed=dut.system_core.failed;
    assign completion_valid=dut.system_core.completion_valid;
    assign completion_ready=dut.system_core.completion_ready;
    assign completion_id=dut.system_core.completion_id;
    assign completion_tile=dut.system_core.completion_tile;
    assign completion_error=dut.system_core.completion_error;

    always #5 clk=~clk;
    rigel_axi_managed_top #(.WORDS_PER_BANK(32)) dut(.*);

    int cyc=0;
    logic aw_saved=0,w_saved=0;
    logic [31:0] saved_addr,saved_data;
    logic [31:0] fake_status=2,fake_src=0,fake_dst=0,fake_bytes=0;
    logic fake_start=0,fake_finished=0;
    int programs=0;
    always @(posedge clk) begin
        cyc<=cyc+1;
        if(!rst_n) begin
            m_axi_bvalid<=0; m_axi_rvalid<=0; m_axi_bresp<=0; m_axi_rresp<=0; m_axi_rdata<=0;
            aw_saved<=0; w_saved<=0; fake_status<=2; fake_start<=0;
        end else begin
            if(m_axi_awvalid && m_axi_awready) begin aw_saved<=1; saved_addr<=m_axi_awaddr; end
            if(m_axi_wvalid && m_axi_wready) begin w_saved<=1; saved_data<=m_axi_wdata; end
            if(aw_saved && w_saved && !m_axi_bvalid) begin
                aw_saved<=0; w_saved<=0; m_axi_bvalid<=1;
                case(saved_addr)
                    0:begin assert(saved_data==4); fake_status<=2; fake_start<=0; end
                    'h18:fake_src<=saved_data;
                    'h20:fake_dst<=saved_data;
                    4:fake_status<=fake_status & ~saved_data;
                    'h28:begin
                        assert(fake_src=='h1000 && fake_dst=='h80000000 && saved_data==64);
                        fake_bytes<=saved_data; fake_status<=0; fake_start<=1; programs<=programs+1;
                    end
                    default:$fatal(1,"bad CDMA address");
                endcase
            end
            if(m_axi_bvalid && m_axi_bready) m_axi_bvalid<=0;
            if(m_axi_arvalid && m_axi_arready) begin
                m_axi_rvalid<=1; m_axi_rdata<=m_axi_araddr==0?0:fake_status;
            end
            if(m_axi_rvalid && m_axi_rready) m_axi_rvalid<=0;
            if(fake_finished) fake_status<=32'h1002;
        end
    end
    always_comb begin
        m_axi_awready=!aw_saved && !m_axi_bvalid && cyc%3!=0;
        m_axi_wready=!w_saved && !m_axi_bvalid && cyc%4!=0;
        m_axi_arready=!m_axi_rvalid && cyc%3!=1;
    end
    function automatic logic [127:0] lanes(input int value);
        return {16{8'(value)}};
    endfunction
    function automatic logic [31:0] enc(input int op,rs0,rs1,imm);
        return (32'(op)<<27)|(32'(rs0)<<16)|(32'(rs1)<<11)|32'(imm);
    endfunction
    task automatic write_burst(input logic [31:0] addr,input int beats,input logic [127:0] value,
        input bit narrow=0,input bit bad_strobe=0,input logic [1:0] expected=0);
        @(negedge clk); s_axi_awaddr=addr; s_axi_awlen=8'(beats-1); s_axi_awsize=narrow?2:4;
        s_axi_awburst=1; s_axi_awid=9; s_axi_awvalid=1;
        do @(posedge clk); while(!s_axi_awready);
        @(negedge clk); s_axi_awvalid=0;
        for(int b=0;b<beats;b++) begin
            s_axi_wvalid=1; s_axi_wlast=b==beats-1;
            s_axi_wstrb=bad_strobe?16'h0001:(narrow?(16'h000f<<addr[3:0]):16'hffff);
            s_axi_wdata=narrow?(value<<(8*addr[3:0])):value;
            do @(posedge clk); while(!s_axi_wready);
            @(negedge clk);
        end
        s_axi_wvalid=0; s_axi_bready=0;
        wait(s_axi_bvalid);
        repeat(4) begin @(negedge clk); assert(s_axi_bvalid && s_axi_bid==9 && s_axi_bresp==expected)
            else $fatal(1,"write response addr=%h actual=%h expected=%h",addr,s_axi_bresp,expected); end
        s_axi_bready=1; @(negedge clk); s_axi_bready=0;
    endtask
    task automatic read_burst(input logic [31:0] addr,input int beats,input logic [127:0] expected,
        input logic [1:0] status=0);
        @(negedge clk); s_axi_araddr=addr; s_axi_arlen=8'(beats-1); s_axi_arsize=4;
        s_axi_arburst=1; s_axi_arid=6; s_axi_arvalid=1;
        do @(posedge clk); while(!s_axi_arready);
        @(negedge clk); s_axi_arvalid=0;
        for(int b=0;b<beats;b++) begin
            s_axi_rready=0; wait(s_axi_rvalid);
            repeat(3) begin @(negedge clk);
                assert(s_axi_rvalid && s_axi_rid==6 && s_axi_rdata==expected && s_axi_rresp==status && s_axi_rlast==(b==beats-1))
                    else $fatal(1,"read mismatch b=%d actual=%h expected=%h",b,s_axi_rdata,expected);
            end
            s_axi_rready=1; @(negedge clk); s_axi_rready=0;
        end
    endtask
    task automatic read_word(input logic [31:0] addr,input logic [31:0] expected);
        @(negedge clk); s_axi_araddr=addr; s_axi_arlen=0; s_axi_arsize=2;
        s_axi_arburst=1; s_axi_arid=3; s_axi_arvalid=1;
        do @(posedge clk); while(!s_axi_arready);
        @(negedge clk); s_axi_arvalid=0; s_axi_rready=0;
        wait(s_axi_rvalid);
        assert((s_axi_rdata >> (8*addr[3:0]))==128'(expected) && s_axi_rresp==0 && s_axi_rlast)
            else $fatal(1,"narrow read addr=%h data=%h expected=%h",addr,s_axi_rdata,expected);
        repeat(3) @(negedge clk);
        s_axi_rready=1; @(negedge clk); s_axi_rready=0;
    endtask
    task automatic write_csr(input int offset,value);
        @(negedge clk); s_task_axi_awaddr=32'(offset); s_task_axi_wdata=32'(value);
        s_task_axi_awvalid=1; s_task_axi_wvalid=1; s_task_axi_wstrb=15;
        do @(posedge clk); while(!s_task_axi_awready || !s_task_axi_wready);
        @(negedge clk); s_task_axi_awvalid=0; s_task_axi_wvalid=0;
        wait(s_task_axi_bvalid); assert(s_task_axi_bresp==0);
        repeat(2) @(negedge clk); s_task_axi_bready=1;
        @(negedge clk); s_task_axi_bready=0;
    endtask
    task automatic read_completion(input logic [31:0] expected);
        @(negedge clk); s_task_axi_araddr=32; s_task_axi_arvalid=1;
        do @(posedge clk); while(!s_task_axi_arready);
        @(negedge clk); s_task_axi_arvalid=0;
        wait(s_task_axi_rvalid);
        repeat(3) begin @(negedge clk);
            assert(s_task_axi_rvalid && s_task_axi_rresp==0 && s_task_axi_rdata==expected);
        end
        s_task_axi_rready=1; @(negedge clk); s_task_axi_rready=0;
    endtask
    task automatic submit(input int id,tile,dep,input bit copy);
        write_csr(4,id|(tile<<8)|((dep>=0?1:0)<<12)|(int'(copy)<<13));
        write_csr(8,dep>=0?dep:0); write_csr(12,32); write_csr(16,'h1000);
        write_csr(20,'h80000000); write_csr(24,64); write_csr(28,1);
    endtask
    initial begin
        wait(fake_start);
        repeat(10) @(negedge clk);
        assert(!busy[1]);
        write_burst(fake_dst,4,lanes(1));
        fake_finished=1;
    end
    int retired=0;
    always @(posedge clk) if(rst_n && completion_valid && completion_ready) begin
        assert(!completion_error);
        if(retired==0) assert(completion_id==1 && completion_tile==1 && fake_finished);
        if(retired==1) assert(completion_id==2 && completion_tile==2 && completed[1]);
        retired<=retired+1;
    end
    initial begin
        s_axi_awaddr=0; s_axi_araddr=0; s_axi_awlen=0; s_axi_arlen=0; s_axi_awsize=0; s_axi_arsize=0; s_axi_awburst=0; s_axi_arburst=0; s_axi_awid=0; s_axi_arid=0; s_axi_awvalid=0; s_axi_wvalid=0; s_axi_bready=0; s_axi_arvalid=0; s_axi_rready=0; s_axi_wdata=0; s_axi_wstrb=0; s_axi_wlast=0; s_task_axi_awaddr=0; s_task_axi_wdata=0; s_task_axi_araddr=0; s_task_axi_wstrb=0; s_task_axi_awvalid=0; s_task_axi_wvalid=0; s_task_axi_bready=0; s_task_axi_arvalid=0; s_task_axi_rready=0;
        repeat(4) @(negedge clk); rst_n=1;
        write_csr(44,15);
        write_burst('h80000000,32,128'h1234);
        read_burst('h80000000,32,128'h1234);
        write_burst('h80000000,2,0,0,1,2);
        read_burst('h80000000,2,128'h1234);
        write_burst('h80000ff0,2,0,0,0,2); // rejected 4K crossing
        read_burst('h80000ff0,2,0,2);
        for(int t=1;t<=2;t++) begin
            write_csr(44,t);
            write_burst('h80000000,4,lanes(1));
            write_burst('h80000080,4,lanes(t+2));
            write_burst('h800c0000,4,lanes(3));
            write_burst('h80040020,1,128'(enc(11,1,2,0)),1);
            write_burst('h80040024,1,128'(enc(11,3,2,1)),1);
            write_burst('h80040028,1,128'(enc(11,6,2,2)),1);
            write_burst('h8004002c,1,128'(enc(13,4,5,0)),1);
            write_burst('h80040030,1,128'(enc(12,0,0,0)),1);
            write_burst('h80040034,1,128'(enc(12,0,0,1)),1);
            write_burst('h80040038,1,128'(enc(12,0,0,2)),1);
            write_burst('h8004003c,1,128'(enc(14,0,0,0)),1);
            write_burst('h80080004,1,0,1);
            write_burst('h80080008,1,64,1);
            write_burst('h8008000c,1,128,1);
            write_burst('h80080010,1,24,1);
            write_burst('h80080014,1,4,1);
            write_burst('h80080018,1,0,1);
            write_burst('h80080040,1,256,1);
            write_burst('h80080044,1,16,1);
            read_word('h80040024,enc(11,3,2,1));
            read_word('h80080000,0); // scheduler status, GPRs are write-only
        end
        submit(1,1,-1,1); submit(2,2,1,0);
        wait(completion_valid); repeat(10) @(negedge clk);
        assert(!completed[1] && !busy[2]); read_completion('h101);
        wait(completion_valid); read_completion('h202);
        wait(retired==2); @(negedge clk);
        assert(completed[1] && completed[2] && programs==1 && fault==0);
        write_csr(44,1); read_burst('h800c0100,4,lanes(10));
        write_csr(44,2); read_burst('h800c0100,4,lanes(13));
        // Reset with a partially supplied burst, then verify clean recovery.
        write_csr(44,15);
        @(negedge clk); s_axi_awaddr='h80000000; s_axi_awlen=1; s_axi_awsize=4; s_axi_awvalid=1;
        do @(posedge clk); while(!s_axi_awready);
        @(negedge clk); s_axi_awvalid=0; s_axi_wvalid=1; s_axi_wlast=0; s_axi_wstrb='1; s_axi_wdata=55;
        do @(posedge clk); while(!s_axi_wready);
        @(negedge clk); s_axi_wvalid=0;
        repeat(5) @(negedge clk); assert(!s_axi_bvalid); rst_n=0;
        repeat(3) @(negedge clk); assert(!s_axi_bvalid && !s_axi_rvalid && completed==0);
        rst_n=1;
        write_burst('h80000000,4,55); read_burst('h80000000,4,55);
        $display("PASS AXI scheduled system: burst commit/readback/stalls/errors, narrow programming, CDMA independent AW/W, copy before launch, dependent FMA jobs");
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end

endmodule
