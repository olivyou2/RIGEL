// Host AXI-Lite descriptor staging + completion consumer. 256-byte CSR window.
module mesh_task_control(
    input logic clk,rst_n,
    input logic [31:0] s_task_axi_awaddr,s_task_axi_wdata,s_task_axi_araddr,
    input logic [3:0] s_task_axi_wstrb,
    input logic s_task_axi_awvalid,s_task_axi_wvalid,s_task_axi_bready,s_task_axi_arvalid,s_task_axi_rready,
    output logic s_task_axi_awready,s_task_axi_wready,s_task_axi_bvalid,s_task_axi_arready,s_task_axi_rvalid,
    output logic [1:0] s_task_axi_bresp,s_task_axi_rresp,
    output logic [31:0] s_task_axi_rdata,
    output logic task_valid, input logic task_ready,
    output logic [7:0] task_id,task_dependency,
    output logic task_has_dependency,task_has_copy,task_copy_only,
    output logic [3:0] task_tile,host_tile,
    output logic [31:0] task_pc,task_src,task_dst,task_bytes,
    input logic submit_error,
    input logic completion_valid, output logic completion_ready,
    input logic [7:0] completion_id,
    input logic [3:0] completion_tile,
    input logic completion_error,
    input logic [255:0] completed,failed,
    input logic [15:0] busy,done,fault
);
    logic ah,wh,pop_completion,rejected;
    logic [7:0] addr;
    logic [31:0] data,header,dependency,pc,src,dst,bytes;
    logic [3:0] strobes;
    assign s_task_axi_awready=rst_n && !ah && !s_task_axi_bvalid;
    assign s_task_axi_wready=rst_n && !wh && !s_task_axi_bvalid;
    assign s_task_axi_arready=rst_n && !s_task_axi_rvalid;
    assign completion_ready=rst_n && s_task_axi_rvalid && s_task_axi_rready && pop_completion;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            ah<=0; wh<=0; addr<=0; data<=0; strobes<=0;
            s_task_axi_bvalid<=0; s_task_axi_bresp<=0;
            s_task_axi_rvalid<=0; s_task_axi_rresp<=0; s_task_axi_rdata<=0;
            pop_completion<=0; rejected<=0; header<=0; dependency<=0; pc<=0; src<=0; dst<=0; bytes<=0;
            task_valid<=0; task_id<=0; task_dependency<=0; task_has_dependency<=0;
            task_has_copy<=0; task_copy_only<=0; task_tile<=0; host_tile<=0;
            task_pc<=0; task_src<=0; task_dst<=0; task_bytes<=0;
        end else begin
            if(submit_error) rejected<=1;
            if(task_valid && task_ready) task_valid<=0;
            if(s_task_axi_awvalid && s_task_axi_awready) begin ah<=1; addr<=s_task_axi_awaddr[7:0]; end
            if(s_task_axi_wvalid && s_task_axi_wready) begin wh<=1; data<=s_task_axi_wdata; strobes<=s_task_axi_wstrb; end
            if(s_task_axi_bvalid && s_task_axi_bready) s_task_axi_bvalid<=0;
            if(ah && wh && !s_task_axi_bvalid) begin
                ah<=0; wh<=0; s_task_axi_bvalid<=1; s_task_axi_bresp<=0;
                if(strobes!=4'hf || addr[1:0]!=0) s_task_axi_bresp<=2'b10;
                else case(addr)
                    8'h00:if(data==2) begin if(!submit_error) rejected<=0; end else s_task_axi_bresp<=2'b10;
                    8'h04:header<=data;
                    8'h08:dependency<=data;
                    8'h0c:pc<=data;
                    8'h10:src<=data;
                    8'h14:dst<=data;
                    8'h18:bytes<=data;
                    8'h1c:if(data==1 && !task_valid && header[31:15]==0 && dependency[31:8]==0) begin
                        task_id<=header[7:0]; task_tile<=header[11:8];
                        task_has_dependency<=header[12]; task_has_copy<=header[13]; task_copy_only<=header[14];
                        task_dependency<=dependency[7:0]; task_pc<=pc; task_src<=src; task_dst<=dst; task_bytes<=bytes;
                        task_valid<=1;
                    end else s_task_axi_bresp<=2'b10;
                    8'h2c:if(data[31:4]==0) host_tile<=data[3:0]; else s_task_axi_bresp<=2'b10;
                    default:s_task_axi_bresp<=2'b10;
                endcase
            end
            if(s_task_axi_rvalid && s_task_axi_rready) begin s_task_axi_rvalid<=0; pop_completion<=0; end
            if(s_task_axi_arvalid && s_task_axi_arready) begin
                s_task_axi_rvalid<=1; s_task_axi_rresp<=0; s_task_axi_rdata<=0; pop_completion<=0;
                if(s_task_axi_araddr[1:0]!=0) s_task_axi_rresp<=2'b10;
                else case(s_task_axi_araddr[7:0])
                    8'h00:s_task_axi_rdata<={29'b0,completion_valid,rejected,task_valid};
                    8'h04:s_task_axi_rdata<=header;
                    8'h08:s_task_axi_rdata<=dependency;
                    8'h0c:s_task_axi_rdata<=pc;
                    8'h10:s_task_axi_rdata<=src;
                    8'h14:s_task_axi_rdata<=dst;
                    8'h18:s_task_axi_rdata<=bytes;
                    8'h20:if(completion_valid) begin
                        s_task_axi_rdata<={19'b0,completion_error,completion_tile,completion_id}; pop_completion<=1;
                    end else s_task_axi_rresp<=2'b10;
                    8'h24:s_task_axi_rdata<={16'b0,busy};
                    8'h28:s_task_axi_rdata<={fault,done};
                    8'h2c:s_task_axi_rdata<={28'b0,host_tile};
                    default:begin
                        if(s_task_axi_araddr[7:5]==3'b010)
                            s_task_axi_rdata<=completed[32*s_task_axi_araddr[4:2]+:32];
                        else if(s_task_axi_araddr[7:5]==3'b011)
                            s_task_axi_rdata<=failed[32*s_task_axi_araddr[4:2]+:32];
                        else s_task_axi_rresp<=2'b10;
                    end
                endcase
            end
        end
    end
endmodule
