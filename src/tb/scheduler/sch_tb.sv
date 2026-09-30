module sch_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    logic running, fault;
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) host_wr();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) mem_req();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) mem_rsp();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(128)) vector_control_req();
    dma_ctrl_if #(.ADDR_WIDTH(32)) ctrl[3]();
    logic [31:0] instruction_mem[0:63];
    int busy[0:2];
    int launch_count[0:2];
    int cycles = 0;
    int emit_count = 0;
    logic stalled_prev = 0;
    logic [31:0] held_addr;
    logic [127:0] held_data;
    logic [31:0] ctrl_src[0:2], ctrl_dst[0:2], ctrl_length[0:2], ctrl_step[0:2];
    logic ctrl_fire[0:2];

    function automatic logic [31:0] enc(
        input logic [4:0] op, input logic ui, input logic [4:0] rd,
        input logic [4:0] rs0, input logic [4:0] rs1, input logic [10:0] imm
    );
        return {op, ui, rd, rs0, rs1, imm};
    endfunction

    task automatic host_write(input logic [31:0] addr, input logic [31:0] data);
        @(negedge clk);
        // Match vector_system's IXC address map: scheduler is select 2.
        host_wr.addr = 32'h0008_0000 | addr;
        host_wr.data = data;
        host_wr.valid = 1;
        @(posedge clk);
        if (!host_wr.ready) $fatal(1, "host write not accepted at %h", addr);
        @(negedge clk);
        host_wr.valid = 0;
    endtask

    for (genvar i = 0; i < 3; i++) begin : ready_map
        assign ctrl[i].ready = (busy[i] == 0);
        assign ctrl_src[i] = ctrl[i].addr_src;
        assign ctrl_dst[i] = ctrl[i].addr_dst;
        assign ctrl_length[i] = ctrl[i].length;
        assign ctrl_step[i] = ctrl[i].step;
        assign ctrl_fire[i] = ctrl[i].valid && ctrl[i].ready;
    end
    assign vector_control_req.ready = cycles % 3 != 0;
    assign mem_req.ready = !mem_rsp.valid || mem_rsp.ready;

    sch #(.SRC_DMA_BEAT_BYTES(16)) dut (
        .clk(clk), .rst_n(rst_n), .write_req(host_wr),
        .mem_read_req(mem_req), .mem_read_rsp(mem_rsp), .dma_ctrl(ctrl),
        .vector_control_req(vector_control_req), .running(running), .fault(fault)
    );

    initial begin
        for (int i = 0; i < 64; i++) instruction_mem[i] = enc(5'd31, 0, 0, 0, 0, 0);
        // PC 0..20 deliberately contain illegal instructions. FIRE starts at 24.
        instruction_mem[6]  = enc(5'd11, 0, 0, 5'd1, 5'd2, 11'd0);
        instruction_mem[7]  = enc(5'd11, 0, 0, 5'd1, 5'd2, 11'd1);
        instruction_mem[8]  = enc(5'd13, 0, 0, 5'd11, 5'd12, 0);
        instruction_mem[9]  = enc(5'd12, 0, 0, 0, 0, 11'd0);
        instruction_mem[10] = enc(5'd12, 0, 0, 0, 0, 11'd1);
        instruction_mem[11] = enc(5'd0, 1, 5'd3, 5'd0, 0, 11'd1);
        instruction_mem[12] = enc(5'd7, 0, 0, 5'd3, 5'd3, 11'd2);
        instruction_mem[13] = enc(5'd13, 0, 0, 5'd11, 5'd12, 0); // stale
        instruction_mem[14] = enc(5'd1, 1, 5'd4, 5'd2, 0, 11'd3);
        instruction_mem[15] = enc(5'd2, 1, 5'd5, 5'd4, 0, 11'd15);
        instruction_mem[16] = enc(5'd3, 1, 5'd5, 5'd5, 0, 11'd5);
        instruction_mem[17] = enc(5'd4, 1, 5'd5, 5'd5, 0, 11'd3);
        instruction_mem[18] = enc(5'd5, 1, 5'd6, 5'd5, 0, 11'd2);
        instruction_mem[19] = enc(5'd6, 1, 5'd7, 5'd6, 0, 11'd1);
        instruction_mem[20] = enc(5'd0, 0, 5'd8, 5'd7, 5'd5, 0);
        instruction_mem[21] = enc(5'd1, 0, 5'd9, 5'd5, 5'd7, 0);
        instruction_mem[22] = enc(5'd0, 1, 5'd10, 5'd0, 0, 11'h7ff);
        instruction_mem[23] = enc(5'd10, 0, 0, 5'd10, 5'd0, 11'd2);
        instruction_mem[24] = enc(5'd13, 0, 0, 5'd11, 5'd12, 0); // stale
        instruction_mem[25] = enc(5'd14, 0, 0, 0, 0, 0); // HALT
        instruction_mem[30] = enc(5'd11, 0, 0, 5'd1, 5'd2, 11'd0);
        instruction_mem[31] = enc(5'd12, 0, 0, 0, 0, 11'd0);
        instruction_mem[32] = enc(5'd14, 0, 0, 0, 0, 0);
        busy[0] = 0; busy[1] = 0; busy[2] = 0;
        launch_count[0] = 0; launch_count[1] = 0; launch_count[2] = 0;
        host_wr.valid = 0; host_wr.addr = 0; host_wr.data = 0;
        host_wr.tag = 0; host_wr.epoch = 0;
        mem_rsp.valid = 0; mem_rsp.addr = 0; mem_rsp.data = 0;
        mem_rsp.epoch = 0; mem_rsp.tag = 0;
        repeat (4) @(posedge clk);
        @(negedge clk) rst_n = 1;
        repeat (5) @(posedge clk);
        if (running || mem_req.valid) $fatal(1, "scheduler did not stay idle");
        host_write(32'h80, 32'd3); // misaligned FIRE is rejected
        if (!fault || running) $fatal(1, "misaligned FIRE did not fault");
        host_write(32'd4, 32'd100);  // r1 source
        host_write(32'd8, 32'd32);   // r2 length
        host_write(32'd44, 32'h106);  // r11 raw control, signed saturation bit
        host_write(32'd48, 32'd3);  // r12 count
        host_write(32'd64, 32'd200); // OUTPUT_BASE
        host_write(32'd68, 32'd8);   // OUTPUT_STEP
        host_write(32'h80, 32'd24); // FIRE at instruction 6
        wait (!running);
        @(negedge clk);
        if (fault || launch_count[0] != 1 || launch_count[1] != 1 || emit_count != 3)
            $fatal(1, "first run failed");
        if (dut.execute.gpr[4] != 96 || dut.execute.gpr[5] != 6 ||
            dut.execute.gpr[6] != 24 || dut.execute.gpr[7] != 12 ||
            dut.execute.gpr[8] != 18 || dut.execute.gpr[9] != 72 ||
            dut.execute.gpr[10] != 32'hffff_ffff)
            $fatal(1, "ALU result mismatch");
        host_write(32'd4, 32'd120); // rewrite r1 while idle
        host_write(32'h80, 32'd120); // FIRE at instruction 30
        wait (!running);
        @(negedge clk);
        if (fault || launch_count[0] != 2 || launch_count[1] != 1 || emit_count != 3)
            $fatal(1, "second run failed");
        $display("sch_tb PASS: host writes, two FIRE PCs, HALT, DMA, EMIT, WAIT");
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (cycles > 400) $fatal(1, "scheduler timed out");
            if (running && host_wr.ready)
                $fatal(1, "host write was accepted while scheduler ran");
            if (stalled_prev && (!vector_control_req.valid ||
                vector_control_req.addr != held_addr ||
                vector_control_req.data != held_data))
                $fatal(1, "control output changed under backpressure");
            stalled_prev <= vector_control_req.valid && !vector_control_req.ready;
            held_addr <= vector_control_req.addr;
            held_data <= vector_control_req.data;
            if (mem_req.valid && mem_req.ready) begin
                mem_rsp.valid <= 1;
                mem_rsp.addr <= mem_req.addr;
                mem_rsp.epoch <= mem_req.epoch;
                mem_rsp.data <= instruction_mem[mem_req.addr[7:2]];
                mem_rsp.tag <= 0;
            end else if (mem_rsp.valid && mem_rsp.ready) begin
                mem_rsp.valid <= 0;
            end
            if (vector_control_req.valid && vector_control_req.ready) begin
                if (vector_control_req.addr != 200 + emit_count * 8 ||
                    vector_control_req.data != 128'h106)
                    $fatal(1, "vector control beat %0d mismatch", emit_count);
                emit_count <= emit_count + 1;
            end
            for (int i = 0; i < 3; i++) begin
                if (busy[i] > 0) busy[i] <= busy[i] - 1;
                if (ctrl_fire[i]) begin
                    launch_count[i] <= launch_count[i] + 1;
                    busy[i] <= 30;
                    if (ctrl_src[i] != ((i == 0 && launch_count[i] == 1) ? 120 : 100) ||
                        ctrl_length[i] != 32 || ctrl_dst[i] != 0 || ctrl_step[i] != 16)
                        $fatal(1, "DMA%0d descriptor mismatch", i);
                end
            end
        end
    end
endmodule
