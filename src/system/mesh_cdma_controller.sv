// Exclusive owner of a 32-bit-address AXI CDMA in simple mode.
// Reset each command, poll reset/idle, program SA/DA/BTT, poll completion.
module mesh_cdma_controller #(parameter logic [31:0] BASE_ADDR=32'h00000000,
    parameter int BTT_WIDTH=23)(
    input logic clk,rst_n,
    input logic copy_valid, output logic copy_ready,
    input logic [31:0] copy_src,copy_dst,copy_bytes,
    output logic copy_done,copy_error,
    output logic [31:0] m_axi_awaddr,m_axi_wdata,m_axi_araddr,
    output logic [2:0] m_axi_awprot,m_axi_arprot,
    output logic [3:0] m_axi_wstrb,
    output logic m_axi_awvalid,m_axi_wvalid,m_axi_bready,m_axi_arvalid,m_axi_rready,
    input logic m_axi_awready,m_axi_wready,m_axi_bvalid,m_axi_arready,m_axi_rvalid,
    input logic [1:0] m_axi_bresp,m_axi_rresp,
    input logic [31:0] m_axi_rdata
);
    typedef enum logic [2:0] {IDLE, WRITE_SEND, WRITE_REPLY, READ_SEND, READ_REPLY} state_t;
    state_t state;
    logic [2:0] step;
    logic aw_pending,w_pending,control_error;
    logic [31:0] src,dst,bytes;
    assign copy_ready=rst_n && state==IDLE;
    assign m_axi_awvalid=rst_n && state==WRITE_SEND && aw_pending;
    assign m_axi_wvalid=rst_n && state==WRITE_SEND && w_pending;
    assign m_axi_bready=rst_n && state==WRITE_REPLY;
    assign m_axi_arvalid=rst_n && state==READ_SEND;
    assign m_axi_rready=rst_n && state==READ_REPLY;
    assign m_axi_awprot=0; assign m_axi_arprot=0; assign m_axi_wstrb=4'hf;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE; step<=0; aw_pending<=0; w_pending<=0; control_error<=0;
            src<=0; dst<=0; bytes<=0; copy_done<=0; copy_error<=0;
            m_axi_awaddr<=0; m_axi_araddr<=0; m_axi_wdata<=0;
        end else begin
            copy_done<=0;
            case(state)
                IDLE: if(copy_valid && copy_ready) begin
                    copy_error<=0; control_error<=0;
                    if(copy_bytes==0 || (copy_bytes >> BTT_WIDTH)!=0 ||
                        copy_bytes[3:0]!=0 || copy_src[3:0]!=0 || copy_dst[3:0]!=0) begin
                        copy_done<=1; copy_error<=1;
                    end else begin
                        src<=copy_src; dst<=copy_dst; bytes<=copy_bytes;
                        step<=0; m_axi_awaddr<=BASE_ADDR; m_axi_wdata<=4;
                        aw_pending<=1; w_pending<=1; state<=WRITE_SEND;
                    end
                end
                WRITE_SEND: begin
                    if(m_axi_awvalid && m_axi_awready) aw_pending<=0;
                    if(m_axi_wvalid && m_axi_wready) w_pending<=0;
                    if((!aw_pending || m_axi_awready) && (!w_pending || m_axi_wready)) state<=WRITE_REPLY;
                end
                WRITE_REPLY: if(m_axi_bvalid) begin
                    if(m_axi_bresp!=0) begin
                        if(step==6) begin
                            // BTT might have started traffic: establish idle before releasing ownership.
                            control_error<=1; m_axi_araddr<=BASE_ADDR+32'h04; step<=7; state<=READ_SEND;
                        end else begin copy_done<=1; copy_error<=1; state<=IDLE; end
                    end
                    else if(step==0) begin m_axi_araddr<=BASE_ADDR; step<=1; state<=READ_SEND; end
                    else if(step==3) begin
                        m_axi_awaddr<=BASE_ADDR+32'h20; m_axi_wdata<=dst;
                        aw_pending<=1; w_pending<=1; step<=4; state<=WRITE_SEND;
                    end else if(step==4) begin
                        m_axi_awaddr<=BASE_ADDR+32'h04; m_axi_wdata<=32'h7000;
                        aw_pending<=1; w_pending<=1; step<=5; state<=WRITE_SEND;
                    end else if(step==5) begin
                        m_axi_awaddr<=BASE_ADDR+32'h28; m_axi_wdata<=bytes;
                        aw_pending<=1; w_pending<=1; step<=6; state<=WRITE_SEND;
                    end else begin m_axi_araddr<=BASE_ADDR+32'h04; step<=7; state<=READ_SEND; end
                end
                READ_SEND: if(m_axi_arready) state<=READ_REPLY;
                READ_REPLY: if(m_axi_rvalid) begin
                    if(m_axi_rresp!=0) begin
                        if(step==7) begin control_error<=1; state<=READ_SEND; end
                        else begin copy_done<=1; copy_error<=1; state<=IDLE; end
                    end
                    else if(step==1) begin
                        if(m_axi_rdata[2]) state<=READ_SEND;
                        else begin m_axi_araddr<=BASE_ADDR+32'h04; step<=2; state<=READ_SEND; end
                    end else if(step==2) begin
                        if(|m_axi_rdata[6:4]) begin copy_done<=1; copy_error<=1; state<=IDLE; end
                        else if(!m_axi_rdata[1]) state<=READ_SEND;
                        else begin
                            m_axi_awaddr<=BASE_ADDR+32'h18; m_axi_wdata<=src;
                            aw_pending<=1; w_pending<=1; step<=3; state<=WRITE_SEND;
                        end
                    end else if(m_axi_rdata[1] && (m_axi_rdata[12] || (|m_axi_rdata[6:4]) || control_error)) begin
                        copy_done<=1; copy_error<=(|m_axi_rdata[6:4]) || control_error; state<=IDLE;
                    end else state<=READ_SEND;
                end
                default:state<=IDLE;
            endcase
        end
    end
    initial assert(BTT_WIDTH>=1 && BTT_WIDTH<=26);
endmodule
