module ixc_control#(
    parameter MASTER_N = 2,
    parameter SLAVE_N = 2,
    parameter SEL_WIDTH = (SLAVE_N > 1) ? $clog2(SLAVE_N) : 1,
    parameter MASTER_WIDTH = (MASTER_N > 1) ? $clog2(MASTER_N) : 1
)(
    input logic clk, rst_n,
    input logic read_addr_valid[MASTER_N], write_data_valid[MASTER_N],
    output logic read_addr_ready[MASTER_N], write_data_ready[MASTER_N],
    input logic [SEL_WIDTH-1:0] read_sel[MASTER_N], write_sel[MASTER_N],
    input logic [SEL_WIDTH-1:0] read_sel_reg[MASTER_N], write_sel_reg[MASTER_N],
    output logic read_load[MASTER_N], write_load[MASTER_N],
    output logic read_pending[MASTER_N], write_pending[MASTER_N],
    output logic write_input_head[MASTER_N], write_input_tail[MASTER_N],
    output logic write_output_head[SLAVE_N], write_output_tail[SLAVE_N],
    output logic read_issue[SLAVE_N], write_issue[SLAVE_N],
    output logic [MASTER_WIDTH-1:0] read_grant[SLAVE_N], write_grant[SLAVE_N],
    output logic [MASTER_WIDTH-1:0] read_owner[SLAVE_N],
    output logic response_load[SLAVE_N],
    output logic slave_read_addr_valid[SLAVE_N], slave_write_data_valid[SLAVE_N],
    input logic slave_read_addr_ready[SLAVE_N], slave_write_data_ready[SLAVE_N],
    input logic slave_read_data_valid[SLAVE_N],
    output logic slave_read_data_ready[SLAVE_N],
    output logic read_data_valid[MASTER_N],
    input logic read_data_ready[MASTER_N]
);
    logic master_busy[MASTER_N];
    logic [MASTER_WIDTH-1:0] write_owner[SLAVE_N][2];
    logic [1:0] write_input_count[MASTER_N], write_output_count[SLAVE_N];
    logic [1:0] write_inflight[MASTER_N];
    logic [SEL_WIDTH-1:0] write_target[MASTER_N];
    logic write_take[MASTER_N], write_retire[MASTER_N];
    logic write_pop[SLAVE_N];
    logic slave_busy[SLAVE_N], read_sent[SLAVE_N];
    logic [MASTER_WIDTH-1:0] read_robin[SLAVE_N], write_robin[SLAVE_N];

    // Only registered state feeds input ready and request arbitration.
    for (genvar m=0; m<MASTER_N; m++) begin: master_control
        assign read_addr_ready[m] = rst_n && !master_busy[m] && (int'(read_sel[m]) < SLAVE_N);
        assign write_data_ready[m] = rst_n && (write_input_count[m] < 2) && (int'(write_sel[m]) < SLAVE_N);
        assign read_load[m] = read_addr_valid[m] && read_addr_ready[m];
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

        // Responses may arrive with the address handshake (zero-cycle slave).
        assign slave_read_data_ready[s] = rst_n && slave_busy[s] &&
            (read_sent[s] || (slave_read_addr_valid[s] && slave_read_addr_ready[s]));
        assign response_load[s] = slave_read_data_valid[s] && slave_read_data_ready[s];

        always_comb begin
            read_issue[s] = 0;
            write_issue[s] = 0;
            read_grant[s] = 0;
            write_grant[s] = 0;
            for (int offset=0; offset<MASTER_N; offset++) begin
                int r, w;
                r = int'(read_robin[s]) + offset;
                w = int'(write_robin[s]) + offset;
                if (r >= MASTER_N) r = r - MASTER_N;
                if (w >= MASTER_N) w = w - MASTER_N;
                if (rst_n && !slave_busy[s] && !read_issue[s] &&
                    read_pending[r] && int'(read_sel_reg[r]) == s) begin
                    read_issue[s] = 1;
                    read_grant[s] = MASTER_WIDTH'(r);
                end
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
            for (int m=0; m<MASTER_N; m++) begin
                master_busy[m] <= 0;
                read_pending[m] <= 0;
                read_data_valid[m] <= 0;
            end
            for (int s=0; s<SLAVE_N; s++) begin
                slave_busy[s] <= 0;
                read_sent[s] <= 0;
                slave_read_addr_valid[s] <= 0;
                read_robin[s] <= 0;
                write_robin[s] <= 0;
                read_owner[s] <= 0;
            end
        end else begin
            for (int m=0; m<MASTER_N; m++) begin
                if (read_data_valid[m] && read_data_ready[m]) begin
                    read_data_valid[m] <= 0;
                    master_busy[m] <= 0;
                end
                if (read_load[m]) begin
                    read_pending[m] <= 1;
                    master_busy[m] <= 1;
                end
            end
            for (int s=0; s<SLAVE_N; s++) begin
                if (slave_read_addr_valid[s] && slave_read_addr_ready[s]) begin
                    slave_read_addr_valid[s] <= 0;
                    read_sent[s] <= 1;
                end
                if (read_issue[s]) begin
                    read_pending[read_grant[s]] <= 0;
                    slave_busy[s] <= 1;
                    read_sent[s] <= 0;
                    read_owner[s] <= read_grant[s];
                    slave_read_addr_valid[s] <= 1;
                    read_robin[s] <= (int'(read_grant[s]) == MASTER_N-1) ?
                        '0 : read_grant[s] + 1'b1;
                end
                if (write_issue[s]) begin
                    write_robin[s] <= (int'(write_grant[s]) == MASTER_N-1) ?
                        '0 : write_grant[s] + 1'b1;
                end
                // Each busy master reserves its response register until consumed.
                if (response_load[s]) begin
                    slave_busy[s] <= 0;
                    read_sent[s] <= 0;
                    read_data_valid[read_owner[s]] <= 1;
                end
            end
        end
    end
endmodule
