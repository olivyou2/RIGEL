module mesh_router#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter CHANNELS = 2,

    parameter X_BITS=2,
    parameter Y_BITS=2,
    parameter X=0,
    parameter Y=0,

    parameter FIFO_DEPTH=8
)(
    input logic clk,
    input logic rst_n,

    // External Router
    input logic [ADDR_WIDTH-1: 0] north_addr_in[CHANNELS],
    input logic [DATA_WIDTH-1: 0] north_data_in[CHANNELS],
    input logic north_data_valid[CHANNELS],
    output logic north_data_ready[CHANNELS],

    input logic [ADDR_WIDTH-1: 0] west_addr_in[CHANNELS],
    input logic [DATA_WIDTH-1: 0] west_data_in[CHANNELS],
    input logic west_data_valid[CHANNELS],
    output logic west_data_ready[CHANNELS],

    output logic [ADDR_WIDTH-1: 0] east_addr_out[CHANNELS],
    output logic [DATA_WIDTH-1: 0] east_data_out[CHANNELS],
    output logic east_data_valid[CHANNELS],
    input logic east_data_ready[CHANNELS],

    output logic [ADDR_WIDTH-1: 0] south_addr_out[CHANNELS],
    output logic [DATA_WIDTH-1: 0] south_data_out[CHANNELS],
    output logic south_data_valid[CHANNELS],
    input logic south_data_ready[CHANNELS],

    // Local In/Out
    input logic [ADDR_WIDTH-1: 0] local_addr_in,
    input logic [DATA_WIDTH-1: 0] local_data_in,
    input logic local_data_in_valid,
    output logic local_data_in_ready,

    output logic [ADDR_WIDTH-1: 0] local_addr_out,
    output logic [DATA_WIDTH-1: 0] local_data_out,
    output logic local_data_out_valid,
    input logic local_data_out_ready
);
    // Parameter Definition
    localparam TOTAL_CHANNEL = CHANNELS*2+1;
    localparam CHANNEL_WIDTH = $clog2(CHANNELS)+2;

    // -----------------------------
    // - Control Definition        -
    // -----------------------------
    //
    // 1. 각 output 별로 valid mask 만듬
    // 2. valid mask 쉬프트
    // 3. 우선순위 인코더로 sel 설정
    // 4. 아웃풋 포트에 valid 올림
    //

    function automatic [X_BITS-1:0] get_x_addr(input logic [ADDR_WIDTH-1: 0] addr_in);
        get_x_addr = addr_in[ADDR_WIDTH-1 -: X_BITS];
    endfunction

    function automatic [X_BITS-1:0] get_y_addr(input logic [ADDR_WIDTH-1: 0] addr_in);
        get_y_addr = addr_in[ADDR_WIDTH-1-X_BITS -: Y_BITS];
    endfunction

    always@(*) begin
        logic [TOTAL_CHANNEL-1: 0] east_valid_chan = 0;
        logic [TOTAL_CHANNEL-1: 0] south_valid_chan = 0;
        logic [TOTAL_CHANNEL-1: 0] local_valid_chan = 0;

        for (int i=0; i<CHANNELS; i++) begin
            if (north_data_valid[i]) begin
                logic [X_BITS-1: 0] north_x = get_x_addr(north_addr_in[i]);
                logic [Y_BITS-1: 0] north_y = get_y_addr(north_addr_in[i]);

                if (X == north_x) begin
                    south_valid_chan[i] = 1;
                end else if (Y != north_y) begin
                    east_valid_chan[i] = 1;
                end else begin
                    local_valid_chan[i] = 1;
                end
            end

            if (west_data_valid[i]) begin
                logic [X_BITS-1: 0] west_x = get_x_addr(west_addr_in[i]);
                logic [Y_BITS-1: 0] west_y = get_y_addr(west_addr_in[i]);

                if (X == west_x) begin
                    south_valid_chan[CHANNELS+i] = 1;
                end if (Y != west_y) begin
                    east_valid_chan[CHANNELS+i] = 1;
                end else begin
                    local_valid_chan[CHANNELS+i] = 1;
                end
            end
        end
    end

    // -----------------------------
    // - Datapath Definition       -
    // -----------------------------

    function automatic [DATA_WIDTH-1: 0] input_data_select(input logic [CHANNEL_WIDTH-1:0] select);
        if (select[CHANNEL_WIDTH-1 -: 2] == 2) begin // North
            input_data_select = north_data_in[
                select[CHANNEL_WIDTH-3:0]
            ];
        end else if (select[CHANNEL_WIDTH-1 -: 2] == 1) begin // West
            input_data_select = west_data_in[
                select[CHANNEL_WIDTH-3:0]
            ];
        end else if (select[CHANNEL_WIDTH-1 -: 2] == 0) begin // Local
            input_data_select = local_data_in;
        end
    endfunction

    function automatic [ADDR_WIDTH-1: 0] input_addr_select(input logic [CHANNEL_WIDTH-1:0] select);
        if (select[CHANNEL_WIDTH-1 -: 2] == 2) begin // North
            input_addr_select = north_addr_in[
                select[CHANNEL_WIDTH-3:0]
            ];
        end else if (select[CHANNEL_WIDTH-1 -: 2] == 1) begin // West
            input_addr_select = west_addr_in[
                select[CHANNEL_WIDTH-3:0]
            ];
        end else if (select[CHANNEL_WIDTH-1 -: 2] == 0) begin // Local
            input_addr_select = local_addr_in;
        end
    endfunction

    logic east_en[CHANNELS];
    logic south_en[CHANNELS];
    logic local_en;

    logic [CHANNEL_WIDTH-1: 0] east_sel[CHANNELS];
    logic [CHANNEL_WIDTH-1: 0] south_sel[CHANNELS];
    logic [CHANNEL_WIDTH-1: 0] local_sel;
    
    always @(posedge clk) begin
        for (int i=0; i<CHANNELS; i++) begin
            if (east_en[i]) begin
                east_data_out[i] <= input_data_select(east_sel[i]);
                east_addr_out[i] <= input_addr_select(east_sel[i]);
            end

            if (south_en[i]) begin
                south_data_out[i] <= input_data_select(south_sel[i]);
                south_addr_out[i] <= input_addr_select(south_sel[i]);
            end
        end

        if (local_en) begin
            local_data_out <= input_data_select(local_sel);
            local_addr_out <= input_addr_select(local_sel);
        end
    end

endmodule;