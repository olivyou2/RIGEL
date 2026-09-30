`timescale 1ns/1ps
module vector_system_throughput_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(128)) rd();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(128)) rsp();
    rv_if #(.ADDR_WIDTH(32), .DATA_WIDTH(128)) wr();
    vector_system dut(.clk(clk), .rst_n(rst_n), .read_req(rd), .read_rsp(rsp), .write_req(wr));

    function automatic logic [31:0] enc(input int op, rs0, rs1, imm);
        return (32'(op) << 27) | (32'(rs0) << 16) | (32'(rs1) << 11) | 32'(imm);
    endfunction

    task automatic host_write(input logic [31:0] addr, input logic [127:0] data);
        @(negedge clk);
        wr.valid = 1;
        wr.addr = addr;
        wr.data = data;
        do @(posedge clk); while (!wr.ready);
        @(negedge clk);
        wr.valid = 0;
    endtask

    int cycle = 0;
    int last_fire = -1;
    int fire_count = 0;
    int last_write = -1;
    int write_count = 0;
    bit trace_on = 0;
    always @(posedge clk) if (rst_n && trace_on) begin
        if (dut.handshake_join_0__out_ch__valid && dut.vector_alu_0__in_ch__ready) begin
            if (last_fire >= 0 && cycle != last_fire + 1)
                $fatal(1, "ALU input bubble: cycle %0d after %0d", cycle, last_fire);
            last_fire = cycle;
            fire_count++;
        end
        if (dut.vector_accumulate_0__out_ch__valid && dut.scratchpad_c__write_req_b__ready) begin
            if (last_write >= 0 && cycle != last_write + 1)
                $fatal(1, "result write bubble: cycle %0d after %0d", cycle, last_write);
            last_write = cycle;
            write_count++;
        end
        cycle <= cycle + 1;
    end

    initial begin
        wr.valid = 0; wr.addr = 0; wr.data = 0; wr.tag = 0; wr.epoch = 0;
        rd.valid = 0; rd.addr = 0; rd.data = 0; rd.tag = 0; rd.epoch = 0;
        rsp.ready = 1;
        repeat (4) @(posedge clk);
        @(negedge clk) rst_n = 1;
        for (int i = 0; i < 8; i++) begin
            host_write(32'(i*16), 128'h01010101010101010101010101010101);
            host_write(32'(128+i*16), 128'h02020202020202020202020202020202);
            host_write(32'(32'hc0000+i*16), 128'h03030303030303030303030303030303);
        end
        host_write(32'h40020, enc(11,1,2,0));
        host_write(32'h40024, enc(11,3,2,1));
        host_write(32'h40028, enc(11,6,2,2));
        host_write(32'h4002c, enc(13,4,5,0));
        host_write(32'h40030, enc(12,0,0,0));
        host_write(32'h40034, enc(12,0,0,1));
        host_write(32'h40038, enc(12,0,0,2));
        host_write(32'h4003c, enc(14,0,0,0));
        host_write(32'h80004, 0);
        host_write(32'h80008, 128);
        host_write(32'h8000c, 128);
        host_write(32'h80010, 24); // raw control: FMA opcode 12
        host_write(32'h80014, 8);
        host_write(32'h80018, 0);
        host_write(32'h80040, 256);
        host_write(32'h80044, 16);
        host_write(32'h80080, 32);
        trace_on = 1;
        repeat (120) @(posedge clk);
        if (fire_count != 8 || write_count != 8)
            $fatal(1, "expected 8 ALU/result beats, got %0d/%0d", fire_count, write_count);
        $display("PASS 8 ALU and result beats without bubbles");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "vector_system throughput test timed out");
    end
endmodule
