// N->1 arbiter

module arbiter#(
    DATA_WIDTH=64,
    N=2
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] data_in[N],
    input logic data_valid[N],
    output logic data_ready[N],

    output logic [DATA_WIDTH-1: 0] data_out,
    output logic data_out_valid,
    input logic data_out_ready
);

    localparam N_WIDTH = $clog2(N);

    initial begin
        if (N <= 0 || (N & (N - 1)) != 0)
            $fatal(1, "N (%0d) must be a power of 2", N);

        if (N == 1)
            $fatal(1, "N must be greater than 1");
    end

    logic [N_WIDTH-1: 0]    robin_idx = 0;

    logic [N_WIDTH-1: 0]    crop_i;
    logic [N_WIDTH-1: 0]    select;
    logic                   select_valid;
    
    logic data_out_handshaked;
    assign data_out_handshaked = data_out_valid && data_out_ready;

    logic writable;
    assign writable = !data_out_valid || data_out_handshaked;

    always_comb begin
        select = 0;
        select_valid = 0;

        for (logic [N_WIDTH: 0] i=0; i<N; i++) begin
            data_ready[i] = 0;
            crop_i = i + robin_idx;

            if (!select_valid && data_valid[crop_i]) begin
                select = crop_i;
                select_valid = 1;
            end
        end

        if (select_valid && writable) begin
            data_ready[select] = 1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            robin_idx <= 0;
            data_out_valid <= 0;
        end else begin
            if (data_out_handshaked) begin
                data_out_valid <= 0;
            end

            if (select_valid && writable) begin
                data_out_valid <= 1;
                data_out <= data_in[select];

                robin_idx <= select + 1;
                // robin_idx <= robin_idx+1;
            end
        end
    end
    
    initial begin
        data_out_valid = 0;
    end

endmodule