module ixc_control#(
    parameter MASTER_N = 2,
    parameter SLAVE_N = 2,
    parameter SEL_WIDTH = (SLAVE_N > 1) ? $clog2(SLAVE_N) : 1,
    parameter MASTER_WIDTH = (MASTER_N > 1) ? $clog2(MASTER_N) : 1
)(
    input logic clk, rst_n,
    input logic write_data_valid[MASTER_N],
    output logic write_data_ready[MASTER_N],
    input logic [SEL_WIDTH-1:0] write_sel[MASTER_N], write_sel_reg[MASTER_N],
    output logic write_load[MASTER_N], write_pending[MASTER_N],
    output logic write_input_head[MASTER_N], write_input_tail[MASTER_N],
    output logic write_output_head[SLAVE_N], write_output_tail[SLAVE_N],
    output logic write_issue[SLAVE_N],
    output logic [MASTER_WIDTH-1:0] write_grant[SLAVE_N],
    output logic slave_write_data_valid[SLAVE_N],
    input logic slave_write_data_ready[SLAVE_N]
);
    // Write control. Pipelined read control lives in ixc_read.
    logic [MASTER_WIDTH-1:0] write_owner[SLAVE_N][2];
    logic [1:0] write_input_count[MASTER_N], write_output_count[SLAVE_N];
    logic [1:0] write_inflight[MASTER_N];
    logic [SEL_WIDTH-1:0] write_target[MASTER_N];
    logic write_take[MASTER_N], write_retire[MASTER_N];
    logic write_pop[SLAVE_N];
    logic [MASTER_WIDTH-1:0] write_robin[SLAVE_N];

    // Only registered state feeds input ready and request arbitration.
    for (genvar m=0; m<MASTER_N; m++) begin: master_control
        assign write_data_ready[m] = rst_n && (write_input_count[m] < 2) && (int'(write_sel[m]) < SLAVE_N);
        assign write_load[m] = write_data_valid[m] && write_data_ready[m];
    end

    // Keep a destination reserved until its queued writes retire. A new
    // destination waits, while same-destination writes can stream every cycle.
    for (genvar m=0; m<MASTER_N; m++) begin: write_master_control
        assign write_pending[m] = write_input_count[m] != 0;
        always_comb begin
            write_take[m] = 0;
            write_retire[m] = 0;
            for (int s=0; s<SLAVE_N; s++) begin
                if (write_issue[s] && int'(write_grant[s]) == m) write_take[m] = 1;
                if (write_pop[s] && int'(write_owner[s][write_output_head[s]]) == m)
                    write_retire[m] = 1;
            end
        end
        always @(posedge clk) begin
            if (!rst_n) begin
                write_input_count[m] <= 0;
                write_input_head[m] <= 0;
                write_input_tail[m] <= 0;
                write_inflight[m] <= 0;
                write_target[m] <= 0;
            end else begin
                case ({write_load[m], write_take[m]})
                    2'b10: write_input_count[m] <= write_input_count[m] + 1'b1;
                    2'b01: write_input_count[m] <= write_input_count[m] - 1'b1;
                    default: begin end
                endcase
                if (write_load[m]) write_input_tail[m] <= ~write_input_tail[m];
                if (write_take[m]) begin
                    write_input_head[m] <= ~write_input_head[m];
                    write_target[m] <= write_sel_reg[m];
                end
                case ({write_take[m], write_retire[m]})
                    2'b10: write_inflight[m] <= write_inflight[m] + 1'b1;
                    2'b01: write_inflight[m] <= write_inflight[m] - 1'b1;
                    default: begin end
                endcase
            end
        end
    end

    for (genvar s=0; s<SLAVE_N; s++) begin: slave_control
        assign slave_write_data_valid[s] = write_output_count[s] != 0;
        assign write_pop[s] = rst_n && slave_write_data_valid[s] && slave_write_data_ready[s];
        always @(posedge clk) begin
            if (!rst_n) begin
                write_output_count[s] <= 0;
                write_output_head[s] <= 0;
                write_output_tail[s] <= 0;
            end else begin
                case ({write_issue[s], write_pop[s]})
                    2'b10: write_output_count[s] <= write_output_count[s] + 1'b1;
                    2'b01: write_output_count[s] <= write_output_count[s] - 1'b1;
                    default: begin end
                endcase
                if (write_pop[s]) write_output_head[s] <= ~write_output_head[s];
                if (write_issue[s]) begin
                    write_owner[s][write_output_tail[s]] <= write_grant[s];
                    write_output_tail[s] <= ~write_output_tail[s];
                end
            end
        end

        always_comb begin
            write_issue[s] = 0;
            write_grant[s] = 0;
            for (int offset=0; offset<MASTER_N; offset++) begin
                int w;
                w = int'(write_robin[s]) + offset;
                if (w >= MASTER_N) w = w - MASTER_N;
                // Deliberately no downstream ready -> grant combinational path.
                if (rst_n && (write_output_count[s] < 2) && !write_issue[s] &&
                    write_pending[w] && int'(write_sel_reg[w]) == s &&
                    (write_inflight[w] == 0 || write_target[w] == write_sel_reg[w])) begin
                    write_issue[s] = 1;
                    write_grant[s] = MASTER_WIDTH'(w);
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int s=0; s<SLAVE_N; s++) write_robin[s] <= 0;
        end else begin
            for (int s=0; s<SLAVE_N; s++) begin
                if (write_issue[s]) begin
                    write_robin[s] <= (int'(write_grant[s]) == MASTER_N-1) ?
                        '0 : write_grant[s] + 1'b1;
                end
            end
        end
    end
endmodule
