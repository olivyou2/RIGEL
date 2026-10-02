// 128-bit AXI4 INCR aperture, 16-byte aligned/full strobes for memory.
// 32-bit single transactions are supported in instruction/CSR windows.
// TILE is sampled at AW/AR. Aperture offset maps to the tile's low 28 bits.
// One read burst and one write burst, independently buffered. Write B is a
// physical-commit barrier: it follows all per-beat mesh acknowledgments.
module mesh_axi_gateway #(parameter logic [31:0] APERTURE_BASE=32'h80000000)(
    input logic clk,rst_n,
    input logic [3:0] destination_tile,
    input logic [31:0] s_axi_awaddr,s_axi_araddr,
    input logic [7:0] s_axi_awlen,s_axi_arlen,
    input logic [2:0] s_axi_awsize,s_axi_arsize,
    input logic [1:0] s_axi_awburst,s_axi_arburst,
    input logic [3:0] s_axi_awid,s_axi_arid,
    input logic s_axi_awvalid,s_axi_wvalid,s_axi_bready,s_axi_arvalid,s_axi_rready,
    output logic s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid,
    input logic [127:0] s_axi_wdata,
    input logic [15:0] s_axi_wstrb,
    input logic s_axi_wlast,
    output logic [3:0] s_axi_bid,s_axi_rid,
    output logic [1:0] s_axi_bresp,s_axi_rresp,
    output logic [127:0] s_axi_rdata,
    output logic s_axi_rlast,
    rv_if.source host_read_req,host_write_req,
    rv_if.sink host_read_rsp,host_write_rsp
);
    logic wa,ra,wbad,rbad,werror,rwaiting,wnarrow,rnarrow;
    logic [15:0] expected_strobe;
    assign expected_strobe=wnarrow ? (16'h000f << waddr[3:0]) : 16'hffff;
    logic [8:0] wtotal,wreceived,wacked,rtotal,rindex;
    logic [31:0] waddr,raddr;
    logic [3:0] rtag;
    function automatic logic bad_burst(input logic [31:0] addr,
        input logic [7:0] len,input logic [2:0] size,input logic [1:0] burst);
        logic [32:0] offset,last_offset;
        offset={1'b0,addr}-{1'b0,APERTURE_BASE};
        last_offset=offset+((33'(len)+33'd1)<<size)-33'd1;
        return !((size==3'd4 && addr[3:0]==0) ||
            (size==3'd2 && len==0 && addr[1:0]==0 &&
             (offset[27:16]==12'h004 || offset[27:16]==12'h008 ||
              offset[27:16]==12'h010 || offset[27:8]==20'hff000))) || burst!=2'b01 ||
            offset[32:28]!=0 || last_offset[32:28]!=0 ||
            ({1'b0,addr[11:0]}+((13'(len)+13'd1)<<size)-13'd1)>13'd4095;
    endfunction
    function automatic logic [31:0] mesh_addr(input logic [31:0] addr,input logic [3:0] tile);
        logic [31:0] offset;
        offset=addr-APERTURE_BASE;
        return {tile[1:0],tile[3:2],offset[27:0]};
    endfunction
    assign s_axi_awready=rst_n && !wa && !s_axi_bvalid;
    assign s_axi_arready=rst_n && !ra && !s_axi_rvalid;
    assign s_axi_wready=rst_n && wa && wreceived<wtotal && (!host_write_req.valid || host_write_req.ready);
    assign host_write_rsp.ready=rst_n && wa && !wbad;
    assign host_read_req.valid=rst_n && ra && !rbad && !rwaiting && !s_axi_rvalid;
    assign host_read_req.addr=raddr; assign host_read_req.data=0;
    assign host_read_req.tag=rtag; assign host_read_req.epoch=0;
    assign host_read_rsp.ready=rst_n && rwaiting && !s_axi_rvalid;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            wa<=0; ra<=0; wbad<=0; rbad<=0; werror<=0; rwaiting<=0; wnarrow<=0; rnarrow<=0;
            wtotal<=0; wreceived<=0; wacked<=0; rtotal<=0; rindex<=0;
            waddr<=0; raddr<=0; rtag<=0;
            s_axi_bvalid<=0; s_axi_bid<=0; s_axi_bresp<=0;
            s_axi_rvalid<=0; s_axi_rid<=0; s_axi_rresp<=0; s_axi_rdata<=0; s_axi_rlast<=0;
            host_write_req.valid<=0; host_write_req.addr<=0; host_write_req.data<=0;
            host_write_req.tag<=0; host_write_req.epoch<=0;
        end else begin
            if(s_axi_awvalid && s_axi_awready) begin
                wa<=1; wnarrow<=s_axi_awsize==3'd2; wbad<=bad_burst(s_axi_awaddr,s_axi_awlen,s_axi_awsize,s_axi_awburst);
                werror<=0; wtotal<={1'b0,s_axi_awlen}+9'd1; wreceived<=0; wacked<=0;
                waddr<=mesh_addr(s_axi_awaddr,destination_tile); s_axi_bid<=s_axi_awid;
            end
            if(host_write_req.valid && host_write_req.ready) host_write_req.valid<=0;
            if(s_axi_wvalid && s_axi_wready) begin
                wreceived<=wreceived+1'b1; waddr<=waddr+(wnarrow?32'd4:32'd16);
                if(s_axi_wlast!=(wreceived==wtotal-1'b1) || s_axi_wstrb!=expected_strobe) werror<=1;
                // A partial strobe is rejected without changing that beat's memory.
                if(!wbad && s_axi_wstrb==expected_strobe) begin
                    host_write_req.valid<=1; host_write_req.addr<=waddr; host_write_req.data<=wnarrow ? {96'b0,s_axi_wdata[8*waddr[3:0]+:32]} : s_axi_wdata;
                    host_write_req.tag<=wreceived[3:0]; host_write_req.epoch<=0;
                end
            end
            case({host_write_rsp.valid && host_write_rsp.ready,
                  s_axi_wvalid && s_axi_wready && !wbad && s_axi_wstrb!=expected_strobe})
                2'b10,2'b01:wacked<=wacked+1'b1;
                2'b11:wacked<=wacked+9'd2;
                default:;
            endcase
            if(host_write_rsp.valid && host_write_rsp.ready && host_write_rsp.data!=0) werror<=1;
            if(wa && !s_axi_bvalid && wreceived==wtotal && !host_write_req.valid && (wbad || wacked==wtotal)) begin
                s_axi_bvalid<=1; s_axi_bresp<=(wbad || werror)?2'b10:2'b00;
            end
            if(s_axi_bvalid && s_axi_bready) begin s_axi_bvalid<=0; wa<=0; end
            if(s_axi_arvalid && s_axi_arready) begin
                ra<=1; rnarrow<=s_axi_arsize==3'd2; rbad<=bad_burst(s_axi_araddr,s_axi_arlen,s_axi_arsize,s_axi_arburst);
                rtotal<={1'b0,s_axi_arlen}+9'd1; rindex<=0; rtag<=0;
                raddr<=mesh_addr(s_axi_araddr,destination_tile); s_axi_rid<=s_axi_arid;
            end
            if(host_read_req.valid && host_read_req.ready) rwaiting<=1;
            if(ra && rbad && !s_axi_rvalid) begin
                s_axi_rvalid<=1; s_axi_rdata<=0; s_axi_rresp<=2'b10; s_axi_rlast<=rindex==rtotal-1'b1;
            end
            if(host_read_rsp.valid && host_read_rsp.ready) begin
                rwaiting<=0; s_axi_rvalid<=1; s_axi_rdata<=rnarrow ? ({96'b0,host_read_rsp.data[31:0]} << (8*raddr[3:0])) : host_read_rsp.data;
                s_axi_rresp<=0; s_axi_rlast<=rindex==rtotal-1'b1;
            end
            if(s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid<=0;
                if(s_axi_rlast) ra<=0;
                else begin rindex<=rindex+1'b1; rtag<=rtag+1'b1; raddr<=raddr+32'd16; end
            end
        end
    end
    initial assert(APERTURE_BASE[27:0]==0);
endmodule
