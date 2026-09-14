`timescale 1ns/1ps
module vector_alu_tb;
    parameter LANE_SIZE=16;
    logic clk=0, rst_n=0;
    logic [7:0] lane_in_a[LANE_SIZE], lane_in_b[LANE_SIZE], lane_out[LANE_SIZE];
    logic lane_sel=0, valid=0, ready, out_valid, out_ready=0;
    logic [4:0] opcode=0;
    typedef logic [LANE_SIZE*8-1:0] result_t;
    result_t expected[$];
    result_t held;
    bit stalled;
    int errors, accepted, consumed, flushed, full_cycles, simultaneous, max_run, run_length;
    int op_count[32];
    int unary_select[2];
    always #5 clk=~clk;
    vector_alu #(.LANE_SIZE(LANE_SIZE)) dut (.*);

    function automatic logic [7:0] reference_op(
        input logic [7:0] a, b, input logic [4:0] op, input logic sel
    );
        int sa, sb, x, value;
        real exponential;
        sa=int'($signed(a)); sb=int'($signed(b));
        x=sel ? sb : sa;
        value=0;
        case (op)
            0: value=sa+sb;
            1: value=sa-sb;
            2: value=sa*sb;
            3: value=int'(a) & int'(b);
            4: value=int'(a) | int'(b);
            5: value=int'(a) ^ int'(b);
            6: value=(b>=8) ? 0 : int'(a)*(2**int'(b));
            // Signed arithmetic right shift is floor(a / 2**shift).
            7: begin
                if (b>=8) value=(sa<0) ? -1 : 0;
                else if (sa>=0) value=sa/(2**int'(b));
                else value=-((-sa+(2**int'(b))-1)/(2**int'(b)));
            end
            8: value=(sa>sb) ? sa : sb;
            9: value=(sa<sb) ? sa : sb;
            10: begin
                exponential=$exp(real'(x));
                value=(exponential>127.0) ? 127 : $rtoi(exponential);
            end
            11: begin
                while ((value+1)*(value+1)<=x) value++;
            end
            default: value=0;
        endcase
        return 8'(value);
    endfunction

    always @(posedge clk) begin
        result_t actual, wanted;
        for (int lane=0; lane<LANE_SIZE; lane++) actual[lane*8+:8]=lane_out[lane];
        if (!rst_n) begin
            flushed+=expected.size();
            expected.delete();
            stalled=0;
            run_length=0;
        end else begin
            if (stalled && (!out_valid || actual!==held)) $fatal(1,"output changed during stall");
            stalled=out_valid && !out_ready;
            held=actual;
            if (!ready) full_cycles++;
            if (out_valid && out_ready) begin
                if (expected.size()==0) $fatal(1,"unexpected/duplicate output");
                wanted=expected.pop_front();
                if (actual!==wanted) begin
                    if (errors<5) $display("MISMATCH got=%h expected=%h",actual,wanted);
                    errors++;
                end
                consumed++;
                run_length++;
                if (run_length>max_run) max_run=run_length;
            end else run_length=0;
            if (valid && ready) begin
                for (int lane=0; lane<LANE_SIZE; lane++)
                    wanted[lane*8+:8]=reference_op(lane_in_a[lane],lane_in_b[lane],opcode,lane_sel);
                expected.push_back(wanted);
                accepted++;
                op_count[opcode]++;
                if (opcode==10 || opcode==11) unary_select[lane_sel]++;
                if (out_valid && out_ready) simultaneous++;
            end
            if (expected.size()>2) $fatal(1,"accepted beyond two-entry buffer capacity");
        end
    end

    // Called at falling edges, and returns at a falling edge after acceptance.
    task automatic send(input int op, a, b, sel, input bit random_stall);
        opcode=5'(op); lane_sel=1'(sel); valid=1;
        for (int lane=0; lane<LANE_SIZE; lane++) begin
            lane_in_a[lane]=8'(a+17*lane);
            lane_in_b[lane]=8'(b+31*lane);
        end
        do begin
            out_ready=random_stall ? ($urandom_range(0,3)==0) : 1;
            @(posedge clk);
            if (ready) begin
                @(negedge clk);
                break;
            end
            @(negedge clk);
        end while (1);
        valid=0;
    endtask

    task automatic drain;
        valid=0; out_ready=1;
        repeat (5) @(negedge clk);
        if (expected.size()!=0 || out_valid) $fatal(1,"failed to drain");
    endtask

    task automatic reset_full;
        drain();
        out_ready=0; valid=1; opcode=0;
        // Two requests fill output and skid; keep a third request waiting.
        repeat (5) @(negedge clk);
        if (ready || !out_valid || expected.size()!=2) $fatal(1,"buffer did not fill");
        rst_n=0; valid=0;
        repeat (2) @(negedge clk);
        if (out_valid || !ready) $fatal(1,"reset state incorrect");
        rst_n=1;
        drain();
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n=1;
        // Directed signed boundaries first so the old implementation reproduces.
        send(8,255,1,0,0); send(9,128,127,0,0); send(7,128,1,0,0);
        drain();
        // Exhaust every pair on every lane for all ten binary opcodes.
        for (int op=0; op<10; op++)
            for (int a=0; a<256; a++)
                for (int b=0; b<256; b++) send(op,a,b,b%2,0);
        for (int op=10; op<12; op++)
            for (int sel=0; sel<2; sel++)
                for (int x=0; x<256; x++) send(op,x,255-x,sel,0);
        for (int op=12; op<32; op++) send(op,255,128,0,0);
        drain();
        reset_full();
        for (int n=0; n<5000; n++) begin
            send(int'($urandom_range(0,31)),int'($urandom_range(0,255)),
                int'($urandom_range(0,255)),int'($urandom_range(0,1)),1);
            if (n%17==0) begin
                valid=0;
                repeat (3) @(negedge clk);
            end
            if (n%1000==999) reset_full();
        end
        drain();
        if (accepted!=consumed+flushed) $fatal(1,"transaction accounting mismatch");
        for (int op=0; op<32; op++)
            if (op_count[op]==0) $fatal(1,"opcode not covered");
        if (full_cycles==0 || simultaneous==0 || max_run<100 || unary_select[0]==0 || unary_select[1]==0)
            $fatal(1,"missing handshake/selection/throughput coverage");
        if (errors!=0) $fatal(1,"%0d result mismatches",errors);
        $display("PASS ALU lanes=%0d accepted=%0d consumed=%0d reset_flushed=%0d full=%0d simultaneous=%0d max_run=%0d",
            LANE_SIZE,accepted,consumed,flushed,full_cycles,simultaneous,max_run);
        $finish;
    end
    initial begin #20000000; $fatal(1,"timeout"); end
endmodule
