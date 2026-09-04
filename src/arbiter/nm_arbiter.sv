// N->M arbiter

module nm_arbiter#(
    DATA_WIDTH=64,
    N=2,
    M=2
)(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1: 0] data_in[N],
    input logic data_valid[N],
    output logic data_ready[N],

    output logic [DATA_WIDTH-1: 0] data_out[M],
    output logic data_out_valid[M],
    input logic data_out_ready[M]
);

    localparam N_WIDTH = $clog2(N);

    initial begin
        if (N <= 0 || (N & (N - 1)) != 0)
            $fatal(1, "N (%0d) must be a power of 2", N);

        if (M > N)
            $fatal(1, "N must be greater or equal than M");

        if (N == 1)
            $fatal(1, "N must be greater than 1");
    end

    logic [N_WIDTH-1: 0]    robin_idx = 0;

    logic [N_WIDTH-1: 0]    crop_i;
    logic [N_WIDTH-1: 0]    select[M];
    logic                   select_valid[M];
    
    logic data_out_handshaked[M];
    logic writable[M];

    always_comb begin
        for (int i=0; i<M; i++) begin
            data_out_handshaked[i] = data_out_valid[i] && data_out_ready[i];
            writable[i] = !data_out_valid[i] || data_out_handshaked[i];
        end 
    end

    always_comb begin
        int select_count;
        select_count = 0;

        for (int i=0; i<M; i++) begin
            select[i] = 0;
            select_valid[i] = 0;
        end

        for (logic [N_WIDTH: 0] i=0; i<N; i++) begin
            data_ready[i] = 0;
            crop_i = i + robin_idx;

            if (select_count != M && data_valid[crop_i]) begin
                select[select_count] = crop_i;
                select_valid[select_count] = 1;

                select_count ++;
            end
        end

        for (int i=0; i<M; i++) begin
            if (select_valid[i] && writable[i]) begin
                data_ready[select[i]] = 1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            robin_idx <= 0;
            for (int i=0; i<M; i++) begin
                data_out_valid[i] <= 0;
            end
        end else begin
            for (int i=0; i<M; i++) begin    
                if (data_out_handshaked[i]) begin
                    data_out_valid[i] <= 0;
                end

                if (select_valid[i] && writable[i]) begin
                    data_out_valid[i] <= 1;
                    data_out[i] <= data_in[select[i]];

                    robin_idx <= select[i] + 1;
                end
            end
        end
    end
    
    initial begin
        for (int i=0; i<M; i++) begin
            data_out_valid[i] = 0;
        end
    end

endmodule