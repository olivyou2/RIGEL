`timescale 1ns/1ps
module mesh_cdma_controller_tb;
    logic clk=0,rst_n=0;
    logic copy_valid; logic copy_ready;
    logic [31:0] copy_src,copy_dst,copy_bytes;
    logic copy_done,copy_error;
    logic [31:0] m_axi_awaddr,m_axi_wdata,m_axi_araddr;
    logic [2:0] m_axi_awprot,m_axi_arprot;
    logic [3:0] m_axi_wstrb;
    logic m_axi_awvalid,m_axi_wvalid,m_axi_bready,m_axi_arvalid,m_axi_rready;
    logic m_axi_awready,m_axi_wready,m_axi_bvalid,m_axi_arready,m_axi_rvalid;
    logic [1:0] m_axi_bresp,m_axi_rresp;
    logic [31:0] m_axi_rdata;

    always #5 clk=~clk;
    mesh_cdma_controller dut(.*);
    int cyc=0, polls=0, commands=0;
    logic aw_saved=0,w_saved=0,started=0;
    logic [31:0] addr,data;
    int mode=0;
    always_comb begin
        m_axi_awready=!aw_saved && !m_axi_bvalid && cyc%3!=0;
        m_axi_wready=!w_saved && !m_axi_bvalid && cyc%4!=0;
        m_axi_arready=!m_axi_rvalid;
    end
    always @(posedge clk) begin
        cyc<=cyc+1;
        if(!rst_n) begin
            aw_saved<=0; w_saved<=0; m_axi_bvalid<=0; m_axi_rvalid<=0;
            m_axi_bresp<=0; m_axi_rresp<=0; m_axi_rdata<=0; started<=0; polls<=0;
        end else begin
            if(m_axi_awvalid && m_axi_awready) begin aw_saved<=1; addr<=m_axi_awaddr; end
            if(m_axi_wvalid && m_axi_wready) begin w_saved<=1; data<=m_axi_wdata; end
            if(aw_saved && w_saved && !m_axi_bvalid) begin
                aw_saved<=0; w_saved<=0; m_axi_bvalid<=1;
                m_axi_bresp<=((mode==2 && addr=='h18) || (mode==4 && addr=='h28)) ? 2'b10 : 2'b00;
                if(addr==0) begin assert(data==4); started<=0; polls<=0; end
                if(addr=='h18) assert(data=='h1000);
                if(addr=='h20) assert(data=='h2000);
                if(addr=='h28) begin assert(data==64); started<=1; commands<=commands+1; end
            end
            if(m_axi_bvalid && m_axi_bready) m_axi_bvalid<=0;
            if(m_axi_arvalid && m_axi_arready) begin
                m_axi_rvalid<=1; m_axi_rresp<=(mode==3 && started && polls==0) ? 2'b10 : 2'b00;
                if(m_axi_araddr==0) m_axi_rdata<=0;
                else if(!started) m_axi_rdata<=2;
                else begin
                    polls<=polls+1;
                    m_axi_rdata<=polls<4?(mode==1?32'h40:0):(mode==1?32'h42:32'h1002);
                end
            end
            if(m_axi_rvalid && m_axi_rready) m_axi_rvalid<=0;
            if(copy_done && mode==1) assert(polls>=5) else $fatal(1,"error reported before CDMA drained");
        end
    end
    task automatic command(input bit expected_error);
        @(negedge clk); copy_valid=1;
        do @(posedge clk); while(!copy_ready);
        @(negedge clk); copy_valid=0;
        wait(copy_done); assert(copy_error==expected_error) else $fatal(1,"CDMA error mismatch");
        @(negedge clk);
    endtask
    initial begin
        copy_valid=0; copy_src='h1000; copy_dst='h2000; copy_bytes=64;
        repeat(3) @(negedge clk); rst_n=1;
        command(0);
        mode=1; command(1);
        mode=2; command(1);
        mode=3; command(1);
        mode=4; command(1);
        mode=0; command(0);
        copy_bytes=0; command(1);
        copy_bytes=32'h800000; command(1);
        copy_bytes=64; copy_src=1; command(1);
        assert(commands==5);
        $display("PASS CDMA controller: separate AW/W stalls, programming/polling, error drain, AXI errors, invalid commands and recovery");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end

endmodule
