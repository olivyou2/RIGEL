// Combinational round-robin picker.
//
// Build one fixed-priority grant for every possible starting position, then
// select between those grants with the registered round-robin pointer.  All
// priority masks are elaboration-time constants, avoiding the serial mux chain
// produced by a loop with a dynamically indexed request vector.
module ixc_rr_arbiter #(
    parameter N = 2,
    parameter INDEX_WIDTH = (N > 1) ? $clog2(N) : 1
) (
    input  logic [N-1:0] request,
    input  logic [INDEX_WIDTH-1:0] priority_idx,
    output logic [N-1:0] grant_onehot,
    output logic grant_valid,
    output logic [INDEX_WIDTH-1:0] grant_index
);
    logic [N-1:0] grant_by_priority[N];

    function automatic logic [N-1:0] earlier_mask(input int start, input int offset);
        earlier_mask = '0;
        for (int k = 0; k < offset; k++)
            earlier_mask[(start + k) % N] = 1'b1;
    endfunction

    for (genvar start = 0; start < N; start++) begin : gen_start
        for (genvar offset = 0; offset < N; offset++) begin : gen_candidate
            localparam int CANDIDATE = (start + offset) % N;
            localparam logic [N-1:0] EARLIER = earlier_mask(start, offset);
            assign grant_by_priority[start][CANDIDATE] =
                request[CANDIDATE] && !(|(request & EARLIER));
        end
    end

    always_comb begin
        grant_onehot = '0;
        for (int p = 0; p < N; p++) begin
            if (int'(priority_idx) == p) grant_onehot = grant_by_priority[p];
        end

        grant_valid = |grant_onehot;
        grant_index = '0;
        for (int p = 0; p < N; p++) begin
            if (grant_onehot[p]) grant_index |= INDEX_WIDTH'(p);
        end
    end

    initial begin
        if (N < 1) $fatal(1, "ixc_rr_arbiter N must be positive");
    end
endmodule
