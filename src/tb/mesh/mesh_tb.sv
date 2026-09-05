module mesh_tb();

    logic clk = 0;
    logic rst_n = 0;

    always #1 clk = !clk;

    localparam DATA_WIDTH = 64;
    localparam ADDR_WIDTH = 32;
    localparam MESH_W = 16;
    localparam MESH_H = 16;
    localparam X_BITS = 4;
    localparam Y_BITS = 4;

    localparam TOTAL_NODES = MESH_W * MESH_H;

    logic [DATA_WIDTH-1:0] data_in[TOTAL_NODES];
    logic [ADDR_WIDTH-1:0] addr_in[TOTAL_NODES];
    logic data_in_valid[TOTAL_NODES];
    logic data_in_ready[TOTAL_NODES];

    logic [DATA_WIDTH-1:0] data_out[TOTAL_NODES];
    logic [ADDR_WIDTH-1:0] addr_out[TOTAL_NODES];
    logic data_out_valid[TOTAL_NODES];
    logic data_out_ready[TOTAL_NODES];

    mesh #(
        .DATA_WIDTH(DATA_WIDTH /* default 64 */),
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .MESH_W    (MESH_W /* default 4 */),
        .MESH_H    (MESH_H /* default 4 */),
        .X_BITS    (X_BITS /* default 2 */),
        .Y_BITS    (Y_BITS /* default 2 */)
     ) mesh (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .addr_in       (addr_in),
        .data_in_valid (data_in_valid),
        .data_in_ready (data_in_ready),
        .data_out      (data_out),
        .addr_out      (addr_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready)
    );

    always @(posedge clk) begin
        int idx=0;

        for (int i=0; i<MESH_W; i++) begin
            for (int j=0; j<MESH_H; j++) begin
                if (data_out_valid[i+j*MESH_W] && data_out_ready[i+j*MESH_W]) begin
                    idx = i+j*MESH_W;
                    $display("[x=%0d, y=%0d] data arrival=%0h, addr=%0h", i, j, data_out[idx], addr_out[idx]);
                end
            end
        end
    end

    task automatic send_packet(input logic [X_BITS-1:0] dst_x, input logic [Y_BITS-1:0] dst_y, input logic [ADDR_WIDTH-1: 0] addr, input logic [DATA_WIDTH-1: 0] data);
        logic [ADDR_WIDTH-1: 0] addr_packet = {
            dst_x, dst_y, addr[ADDR_WIDTH-1-X_BITS-Y_BITS: 0]
        };

        data_in_valid[0] = 1;
        data_in[0] = data;
        addr_in[0] = addr_packet;
        
        do begin
            @(posedge clk);
        end while(!data_in_ready[0]);

        @(negedge clk);
        data_in_valid[0] = 0;

        $display("packet sent, dst_x=%0d, dst_y=%0d, data=%0h", dst_x, dst_y, data);
    endtask

    int idx;
    initial begin
        for (int i=0; i<TOTAL_NODES; i++) begin
            data_out_ready[i] = 1;
        end

        rst_n = 0;
        #10;
        rst_n = 1;
        #10;

        @(negedge clk);

        for (int x=0; x<MESH_W; x++) begin
            for (int y=0; y<MESH_H; y++) begin
                 idx = x+y*MESH_W;
                send_packet(x, y /* logic[1:0] */, 0 /* logic[31:0] */, 64'hdeadbeef00000000 + idx /* logic[63:0] */);
            end
        end

        #1000;
        $finish();
    end

endmodule