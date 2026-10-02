// 16 vector tiles on two registered, non-wrapping 4x4 XY meshes.
// Host gateway shares tile (0,0)'s injection port with its local copy engine.
module rigel_mesh_system #(parameter int WORDS_PER_BANK=512, WRITE_DEPTH=8, HOST_LAUNCH=1)(
    input logic clk, rst_n,
    rv_if.sink host_read_req, host_write_req,
    rv_if.source host_read_rsp, host_write_rsp,
    input logic [15:0] scheduled_launch, scheduled_reserved,
    input logic [31:0] scheduled_pc,
    output logic [15:0] busy, done, fault
);
    logic [15:0] launch;
    logic [31:0] launch_pc;
    rv_if #(.DATA_WIDTH(128)) gateway_rd(), gateway_wr(), gateway_rp(), gateway_wp();
    mesh_system_control #(.WRITE_DEPTH(WRITE_DEPTH),.HOST_LAUNCH(HOST_LAUNCH)) control(.clk(clk),.rst_n(rst_n),.busy(busy),.done(done),.fault(fault),
        .scheduled_launch(scheduled_launch),.scheduled_reserved(scheduled_reserved),.scheduled_pc(scheduled_pc),
        .launch(launch),.launch_pc(launch_pc),.host_read_req(host_read_req),.host_write_req(host_write_req),
        .host_read_rsp(host_read_rsp),.host_write_rsp(host_write_rsp),
        .gateway_read_req(gateway_rd),.gateway_write_req(gateway_wr),
        .gateway_read_rsp(gateway_rp),.gateway_write_rsp(gateway_wp));
    rv_if #(.DATA_WIDTH(133)) req_tx[16](), req_rx[16](), rsp_tx[16](), rsp_rx[16]();
    mesh_xy requests(.clk(clk),.rst_n(rst_n),.in_ch(req_tx),.out_ch(req_rx));
    mesh_xy responses(.clk(clk),.rst_n(rst_n),.in_ch(rsp_tx),.out_ch(rsp_rx));
    for(genvar n=0;n<16;n++) begin : tiles
        rv_if #(.DATA_WIDTH(128)) outgoing_rd(), outgoing_wr(), outgoing_rp(), outgoing_wp();
        rv_if #(.DATA_WIDTH(128)) endpoint_rd(), endpoint_wr(), endpoint_rp(), endpoint_wp();
        rv_if #(.DATA_WIDTH(128)) copy_rd(), copy_wr(), copy_rp(), copy_wp();
        logic tile_busy, tile_done, tile_fault;
        mesh_ni #(.X(n%4),.Y(n/4),.WRITE_DEPTH(WRITE_DEPTH)) ni(.clk(clk),.rst_n(rst_n),
            .read_req(outgoing_rd),.write_req(outgoing_wr),.read_rsp(outgoing_rp),.write_rsp(outgoing_wp),
            .target_read_req(endpoint_rd),.target_write_req(endpoint_wr),
            .target_read_rsp(endpoint_rp),.target_write_rsp(endpoint_wp),
            .req_tx(req_tx[n]),.req_rx(req_rx[n]),.rsp_tx(rsp_tx[n]),.rsp_rx(rsp_rx[n]));
        logic local_launch;
        logic [31:0] local_pc;
        always_ff @(posedge clk) begin
            if(!rst_n) begin local_launch<=0; local_pc<=0; end
            else begin local_launch<=launch[n]; local_pc<=launch_pc; end
        end
        vector_tile #(.WORDS_PER_BANK(WORDS_PER_BANK),.WRITE_DEPTH(WRITE_DEPTH)) tile(.clk(clk),.rst_n(rst_n),.launch(local_launch),.launch_pc(local_pc),
            .read_req(endpoint_rd),.write_req(endpoint_wr),.read_rsp(endpoint_rp),.write_rsp(endpoint_wp),
            .copy_read_req(copy_rd),.copy_write_req(copy_wr),.copy_read_rsp(copy_rp),.copy_write_rsp(copy_wp),
            .busy(tile_busy),.done(tile_done),.fault(tile_fault));
        // Registered aggregation avoids a long combinational status cone.
        always_ff @(posedge clk) begin
            if(!rst_n) begin busy[n]<=0; done[n]<=0; fault[n]<=0; end
            else begin busy[n]<=tile_busy; done[n]<=tile_done; fault[n]<=tile_fault; end
        end
        if(n==0) begin : gateway
            rv_if #(.DATA_WIDTH(128)) rd[2](), wr[2](), rp[2](), wp[2]();
            assign rd[0].valid=gateway_rd.valid;
            assign rd[0].addr=gateway_rd.addr;
            assign rd[0].data=gateway_rd.data;
            assign rd[0].tag=gateway_rd.tag;
            assign rd[0].epoch=gateway_rd.epoch;
            assign gateway_rd.ready=rd[0].ready;
            assign wr[0].valid=gateway_wr.valid;
            assign wr[0].addr=gateway_wr.addr;
            assign wr[0].data=gateway_wr.data;
            assign wr[0].tag=gateway_wr.tag;
            assign wr[0].epoch=gateway_wr.epoch;
            assign gateway_wr.ready=wr[0].ready;
            assign gateway_rp.valid=rp[0].valid;
            assign gateway_rp.addr=rp[0].addr;
            assign gateway_rp.data=rp[0].data;
            assign gateway_rp.tag=rp[0].tag;
            assign gateway_rp.epoch=rp[0].epoch;
            assign rp[0].ready=gateway_rp.ready;
            assign gateway_wp.valid=wp[0].valid;
            assign gateway_wp.addr=wp[0].addr;
            assign gateway_wp.data=wp[0].data;
            assign gateway_wp.tag=wp[0].tag;
            assign gateway_wp.epoch=wp[0].epoch;
            assign wp[0].ready=gateway_wp.ready;
            assign rd[1].valid=copy_rd.valid;
            assign rd[1].addr=copy_rd.addr;
            assign rd[1].data=copy_rd.data;
            assign rd[1].tag=copy_rd.tag;
            assign rd[1].epoch=copy_rd.epoch;
            assign copy_rd.ready=rd[1].ready;
            assign wr[1].valid=copy_wr.valid;
            assign wr[1].addr=copy_wr.addr;
            assign wr[1].data=copy_wr.data;
            assign wr[1].tag=copy_wr.tag;
            assign wr[1].epoch=copy_wr.epoch;
            assign copy_wr.ready=wr[1].ready;
            assign copy_rp.valid=rp[1].valid;
            assign copy_rp.addr=rp[1].addr;
            assign copy_rp.data=rp[1].data;
            assign copy_rp.tag=rp[1].tag;
            assign copy_rp.epoch=rp[1].epoch;
            assign rp[1].ready=copy_rp.ready;
            assign copy_wp.valid=wp[1].valid;
            assign copy_wp.addr=wp[1].addr;
            assign copy_wp.data=wp[1].data;
            assign copy_wp.tag=wp[1].tag;
            assign copy_wp.epoch=wp[1].epoch;
            assign wp[1].ready=copy_wp.ready;
            ni_source_mux #(.WRITE_DEPTH(WRITE_DEPTH)) sources(.clk(clk),.rst_n(rst_n),.read_req(rd),.write_req(wr),
                .read_rsp(rp),.write_rsp(wp),.ni_read_req(outgoing_rd),.ni_write_req(outgoing_wr),
                .ni_read_rsp(outgoing_rp),.ni_write_rsp(outgoing_wp));
        end else begin : copy_only
            assign outgoing_rd.valid=copy_rd.valid;
            assign outgoing_rd.addr=copy_rd.addr;
            assign outgoing_rd.data=copy_rd.data;
            assign outgoing_rd.tag=copy_rd.tag;
            assign outgoing_rd.epoch=copy_rd.epoch;
            assign copy_rd.ready=outgoing_rd.ready;
            assign outgoing_wr.valid=copy_wr.valid;
            assign outgoing_wr.addr=copy_wr.addr;
            assign outgoing_wr.data=copy_wr.data;
            assign outgoing_wr.tag=copy_wr.tag;
            assign outgoing_wr.epoch=copy_wr.epoch;
            assign copy_wr.ready=outgoing_wr.ready;
            assign copy_rp.valid=outgoing_rp.valid;
            assign copy_rp.addr=outgoing_rp.addr;
            assign copy_rp.data=outgoing_rp.data;
            assign copy_rp.tag=outgoing_rp.tag;
            assign copy_rp.epoch=outgoing_rp.epoch;
            assign outgoing_rp.ready=copy_rp.ready;
            assign copy_wp.valid=outgoing_wp.valid;
            assign copy_wp.addr=outgoing_wp.addr;
            assign copy_wp.data=outgoing_wp.data;
            assign copy_wp.tag=outgoing_wp.tag;
            assign copy_wp.epoch=outgoing_wp.epoch;
            assign outgoing_wp.ready=copy_wp.ready;
        end
    end
endmodule
