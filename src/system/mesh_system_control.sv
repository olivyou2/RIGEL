// Host control page 0x0ff00000; other addresses forward to the tile-0 gateway.
// Registers: +00 busy, +04 done, +08 fault, +0c active mask,
// +10 launch mask (RW), +14 local instruction PC (RW), +18 launch (write 1),
// +1c all selected jobs completed (read). Launch is accepted only if idle.
module mesh_system_control #(parameter int WRITE_DEPTH=8, HOST_LAUNCH=1)(
    input logic clk, rst_n,
    input logic [15:0] busy, done, fault,
    input logic [15:0] scheduled_launch, scheduled_reserved,
    input logic [31:0] scheduled_pc,
    output logic [15:0] launch,
    output logic [31:0] launch_pc,
    rv_if.sink host_read_req, host_write_req,
    rv_if.source host_read_rsp, host_write_rsp,
    rv_if.source gateway_read_req, gateway_write_req,
    rv_if.sink gateway_read_rsp, gateway_write_rsp
);
    localparam int CNT=$clog2(WRITE_DEPTH+1);
    logic [CNT-1:0] forwarded;
    logic rd_busy, rd_local;
    logic rv, wv, completed;
    logic [15:0] mask, active, armed;
    logic [31:0] ra, wa, pc;
    logic [127:0] rd, wd;
    logic [3:0] rt, re, wt, we;
    wire read_control=host_read_req.addr[31:8]==24'h0ff000;
    wire write_control=host_write_req.addr[31:8]==24'h0ff000;
    assign host_read_req.ready=rst_n && !rd_busy && (read_control || gateway_read_req.ready);
    assign host_write_req.ready=rst_n && !wv && (write_control ?
        forwarded==0 : (forwarded<CNT'(WRITE_DEPTH) && gateway_write_req.ready));
    assign gateway_read_req.valid=rst_n && !rd_busy && !read_control && host_read_req.valid;
    assign gateway_write_req.valid=rst_n && !wv && forwarded<CNT'(WRITE_DEPTH) &&
        !write_control && host_write_req.valid;
    assign gateway_read_req.addr=host_read_req.addr;
    assign gateway_read_req.data=host_read_req.data;
    assign gateway_read_req.tag=host_read_req.tag;
    assign gateway_read_req.epoch=host_read_req.epoch;
    assign gateway_write_req.addr=host_write_req.addr;
    assign gateway_write_req.data=host_write_req.data;
    assign gateway_write_req.tag=host_write_req.tag;
    assign gateway_write_req.epoch=host_write_req.epoch;
    assign host_read_rsp.valid=rst_n && rd_busy && (rd_local ? rv : gateway_read_rsp.valid);
    assign host_read_rsp.addr=rd_local ? ra : gateway_read_rsp.addr;
    assign host_read_rsp.data=rd_local ? rd : gateway_read_rsp.data;
    assign host_read_rsp.tag=rd_local ? rt : gateway_read_rsp.tag;
    assign host_read_rsp.epoch=rd_local ? re : gateway_read_rsp.epoch;
    assign host_write_rsp.valid=rst_n && (wv || (forwarded!=0 && gateway_write_rsp.valid));
    assign host_write_rsp.addr=wv ? wa : gateway_write_rsp.addr;
    assign host_write_rsp.data=wv ? wd : gateway_write_rsp.data;
    assign host_write_rsp.tag=wv ? wt : gateway_write_rsp.tag;
    assign host_write_rsp.epoch=wv ? we : gateway_write_rsp.epoch;
    assign gateway_read_rsp.ready=rst_n && rd_busy && !rd_local && host_read_rsp.ready;
    assign gateway_write_rsp.ready=rst_n && !wv && forwarded!=0 && host_write_rsp.ready;
    assign launch_pc=pc;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            rd_busy<=0; rd_local<=0; forwarded<=0; rv<=0; wv<=0;
            mask<=0; active<=0; armed<=0; pc<=0; launch<=0; completed<=0;
            ra<=0; wa<=0; rd<=0; wd<=0; rt<=0; re<=0; wt<=0; we<=0;
        end else begin
            launch<=scheduled_launch;
            if(scheduled_launch!=0) pc<=scheduled_pc;
            case({gateway_write_req.valid && gateway_write_req.ready,
                  gateway_write_rsp.valid && gateway_write_rsp.ready})
                2'b10:forwarded<=forwarded+1'b1;
                2'b01:forwarded<=forwarded-1'b1;
                default:;
            endcase
            armed<=armed | (busy & active);
            if(active!=0 && (armed & active)==active && (done & active)==active && (busy & active)==0) begin
                active<=0; completed<=1;
            end
            if(host_read_rsp.valid && host_read_rsp.ready) begin rd_busy<=0; rv<=0; end
            if(host_write_rsp.valid && host_write_rsp.ready && wv) wv<=0;
            if(host_read_req.valid && host_read_req.ready) begin
                rd_busy<=1; rd_local<=read_control;
                if(read_control) begin
                    rv<=1; ra<=host_read_req.addr; rt<=host_read_req.tag; re<=host_read_req.epoch;
                    case(host_read_req.addr[7:0])
                        8'h00:rd<=128'(busy);
                        8'h04:rd<=128'(done);
                        8'h08:rd<=128'(fault);
                        8'h0c:rd<=128'(active);
                        8'h10:rd<=128'(mask);
                        8'h14:rd<=128'(pc);
                        8'h1c:rd<=128'(completed);
                        default:rd<=0;
                    endcase
                end
            end
            if(host_write_req.valid && host_write_req.ready) begin
                if(write_control) begin
                    wv<=1; wa<=host_write_req.addr; wt<=host_write_req.tag; we<=host_write_req.epoch; wd<=0;
                    case(host_write_req.addr[7:0])
                        8'h10:if(active==0) mask<=host_write_req.data[15:0]; else wd<=1;
                        8'h14:if(active==0 && host_write_req.data[1:0]==0) pc<=host_write_req.data[31:0]; else wd<=1;
                        8'h18:if(HOST_LAUNCH!=0 && host_write_req.data==1 && active==0 && scheduled_reserved==0 && scheduled_launch==0 && (busy & mask)==0) begin
                            launch<=mask; active<=mask; armed<=0; completed<=mask==0;
                        end else wd<=1;
                        default:wd<=1;
                    endcase
                end
            end
        end
    end
endmodule
