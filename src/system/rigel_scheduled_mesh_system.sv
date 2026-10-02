// Scheduled system boundary. Copy port connects to a DMA controller;
// host ready/valid port connects to the future AXI-MM gateway adapter.
module rigel_scheduled_mesh_system #(parameter int WORDS_PER_BANK=512, WRITE_DEPTH=8, QUEUE_DEPTH=4)(
    input logic clk, rst_n,
    rv_if.sink host_read_req, host_write_req,
    rv_if.source host_read_rsp, host_write_rsp,
    input logic task_valid, output logic task_ready,
    input logic [7:0] task_id, task_dependency,
    input logic task_has_dependency, task_has_copy, task_copy_only,
    input logic [3:0] task_tile,
    input logic [31:0] task_pc, task_src, task_dst, task_bytes,
    output logic submit_error,
    output logic copy_valid, input logic copy_ready,
    output logic [3:0] copy_tile,
    output logic [31:0] copy_src, copy_dst, copy_bytes,
    input logic copy_done, copy_error,
    output logic completion_valid, input logic completion_ready,
    output logic [7:0] completion_id,
    output logic [3:0] completion_tile,
    output logic completion_error,
    output logic [255:0] completed, failed,
    output logic [15:0] busy, done, fault
);
    logic [15:0] reserved, launch;
    logic [31:0] launch_pc;
    mesh_task_scheduler #(.QUEUE_DEPTH(QUEUE_DEPTH)) scheduler(
        .clk(clk),.rst_n(rst_n),.task_valid(task_valid),.task_ready(task_ready),
        .task_id(task_id),.task_dependency(task_dependency),.task_has_dependency(task_has_dependency),
        .task_has_copy(task_has_copy),.task_copy_only(task_copy_only),.task_tile(task_tile),.task_pc(task_pc),.task_src(task_src),
        .task_dst(task_dst),.task_bytes(task_bytes),.submit_error(submit_error),
        .tile_busy(busy),.tile_done(done),.tile_fault(fault),.reserved(reserved),.launch(launch),.launch_pc(launch_pc),
        .copy_valid(copy_valid),.copy_ready(copy_ready),.copy_tile(copy_tile),.copy_src(copy_src),.copy_dst(copy_dst),.copy_bytes(copy_bytes),
        .copy_done(copy_done),.copy_error(copy_error),.completion_valid(completion_valid),
        .completion_ready(completion_ready),.completion_id(completion_id),.completion_tile(completion_tile),
        .completion_error(completion_error),.completed(completed),.failed(failed));
    rigel_mesh_system #(.WORDS_PER_BANK(WORDS_PER_BANK),.WRITE_DEPTH(WRITE_DEPTH),.HOST_LAUNCH(0)) mesh(
        .clk(clk),.rst_n(rst_n),.host_read_req(host_read_req),.host_write_req(host_write_req),
        .host_read_rsp(host_read_rsp),.host_write_rsp(host_write_rsp),.scheduled_launch(launch),
        .scheduled_reserved(reserved),.scheduled_pc(launch_pc),.busy(busy),.done(done),.fault(fault));
endmodule
