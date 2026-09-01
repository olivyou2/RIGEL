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
    localparam CHANNEL_WIDTH = $clog2(CHANNELS);

    // -----------------------------
    // - Controlpath               -
    // -----------------------------

    function automatic [X_BITS-1:0] get_x_addr(input logic [ADDR_WIDTH-1: 0] addr_in);
        get_x_addr = addr_in[ADDR_WIDTH-1 -: X_BITS];
    endfunction

    function automatic [Y_BITS-1:0] get_y_addr(input logic [ADDR_WIDTH-1: 0] addr_in);
        get_y_addr = addr_in[ADDR_WIDTH-1-X_BITS -: Y_BITS];
    endfunction

    function automatic logic mask_valid(input logic [TOTAL_CHANNEL-1: 0] mask, input logic [CHANNEL_WIDTH-1: 0] th);
        logic [CHANNEL_WIDTH-1: 0] cont_count;
        
        cont_count = 0;
        mask_valid = 0;

        for (int i=0; i<TOTAL_CHANNEL; i++) begin
            if (mask[i]) begin
                if (cont_count != th) begin
                    cont_count = cont_count + 1;
                    continue;
                end
                mask_valid = 1;
                break;
            end
        end
    endfunction

    function automatic [CHANNEL_WIDTH-1: 0] mask_idx(input logic [TOTAL_CHANNEL-1: 0] mask, input logic [CHANNEL_WIDTH-1: 0] th);
        logic [CHANNEL_WIDTH-1: 0] cont_count;
        
        cont_count = 0;
        mask_idx = 0;

        for (logic [CHANNEL_WIDTH-1: 0] i=0; i<TOTAL_CHANNEL; i++) begin
            if (mask[i]) begin
                if (cont_count != th) begin
                    cont_count = cont_count + 1;
                    continue;
                end
                mask_idx = i;
                break;
            end
        end
    endfunction

    always@(*) begin
        // mask
        
        logic [TOTAL_CHANNEL-1: 0] east_valid_chan = 0;
        logic [TOTAL_CHANNEL-1: 0] south_valid_chan = 0;
        logic [TOTAL_CHANNEL-1: 0] local_valid_chan = 0;
        
        // select

        logic [$clog2(CHANNELS): 0] east_channel_count = 0;
        logic [$clog2(CHANNELS): 0] south_channel_count = 0;
        logic [1:0] local_channel_count = 0;

        // logic

        logic [X_BITS-1: 0] addr_x = 0;
        logic [Y_BITS-1: 0] addr_y = 0;
            
            // masking logic
        for (int i=0; i<CHANNELS; i++) begin
            if (north_data_valid[i]) begin
                addr_x = get_x_addr(north_addr_in[i]);
                addr_y = get_y_addr(north_addr_in[i]);

                if (X == addr_x) begin
                    south_valid_chan[i] = 1;
                end else if (Y == addr_y) begin
                    east_valid_chan[i] = 1;
                end else begin
                    local_valid_chan[i] = 1;
                end
            end

            if (west_data_valid[i]) begin
                addr_x = get_x_addr(west_addr_in[i]);
                addr_y = get_y_addr(west_addr_in[i]);

                if (X == addr_x) begin
                    south_valid_chan[CHANNELS+i] = 1;
                end else if (Y == addr_y) begin
                    east_valid_chan[CHANNELS+i] = 1;
                end else begin
                    local_valid_chan[CHANNELS+i] = 1;
                end
            end
        end

        if (local_data_in) begin
            addr_x = get_x_addr(local_addr_in);
            addr_y = get_y_addr(local_addr_in);

            if (X == addr_x) begin
                south_valid_chan[CHANNELS*2] = 1;
            end else if (Y == addr_y) begin
                east_valid_chan[CHANNELS*2] = 1;
            end else begin
                local_valid_chan[CHANNELS*2] = 1;
            end
        end

        for (int i=0; i<CHANNELS; i++) begin
            east_sel[i] = 0;
            south_sel[i] = 0;
            local_sel = 0;
            east_data_valid[i] = 0;
            south_data_valid[i] = 0;
            local_data_out_valid = 0;
        end

            // priority indexing && valid on
        for (int i=0; i<TOTAL_CHANNEL; i++) begin
            logic channel_selected = 0;

            north_data_ready[i] = 0;
            west_data_ready[i] = 0;
            local_data_in_ready = 0;
            
            if (east_valid_chan[i] && (east_channel_count < CHANNELS)) begin
                east_sel[east_channel_count] = i;
                east_data_valid[east_channel_count] = 1;
                east_channel_count ++;

                channel_selected = 1;
            end
            
            if (south_valid_chan[i] && (south_channel_count < CHANNELS)) begin
                south_sel[south_channel_count] = i;
                south_data_valid[south_channel_count] = 1;
                south_channel_count ++;

                channel_selected = 1;
            end

            if (local_valid_chan[i] && (local_channel_count == 0)) begin
                local_sel = i;
                local_data_out_valid = 1;
                local_channel_count ++;

                channel_selected = 1;
            end

            if (channel_selected) begin
                if (channel_selected < CHANNELS) begin
                    north_data_ready[i] = 1;
                end else if (channel_selected < CHANNELS * 2) begin
                    west_data_ready[i - CHANNELS] = 1;
                end else begin
                    local_data_in_ready = 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            // Ready/Valid Initialize
            for (int i=0; i<CHANNELS; i++) begin
                // north_data_ready[i] <= 1;
                // west_data_ready[i]  <= 1;

                // south_data_valid[i] <= 0;
                // east_data_valid[i]  <= 0;
            end 

            // local_data_in_ready     <= 1;
            // local_data_out_valid    <= 0;
        end else begin
            // Output consume
            // for (int i=0; i<CHANNELS; i++) begin
            //     if (south_data_valid[i] && south_data_ready[i]) south_data_valid[i] <= 0;
            //     if (east_data_valid[i] && east_data_ready[i]) east_data_valid[i] <= 0;
            // end
            // if (local_data_out_valid && local_data_out_ready) local_data_out_valid <= 0;

            // Output provide
        end
    end

    // -----------------------------
    // - Datapath Definition       -
    // -----------------------------

    function automatic [DATA_WIDTH-1: 0] input_data_select(input logic [CHANNEL_WIDTH-1:0] select);
        if (select < CHANNELS) begin
            input_data_select = north_data_in[select];
        end else if (select < CHANNELS*2) begin
            input_data_select = west_data_in[select - CHANNELS];
        end else begin
            input_data_select = local_data_in;
        end
    endfunction

    function automatic [ADDR_WIDTH-1: 0] input_addr_select(input logic [CHANNEL_WIDTH-1:0] select);
        if (select < CHANNELS) begin
            input_addr_select = north_addr_in[select];
        end else if (select < CHANNELS*2) begin
            input_addr_select = west_addr_in[select - CHANNELS];
        end else begin
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