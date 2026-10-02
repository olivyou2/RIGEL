// One outstanding remote write per NI. Request and ACK use separate networks.
// The target write handshake must mean endpoint acceptance/commit, not enqueue
// into another interconnect. Reset all NIs, networks and endpoints together.
module mesh_write_ni #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 128,
    parameter int TAG_WIDTH = 4,
    parameter int EPOCH_WIDTH = 4,
    parameter int X_BITS = 2,
    parameter int Y_BITS = 2,
    parameter logic [X_BITS-1:0] X = '0,
    parameter logic [Y_BITS-1:0] Y = '0
)(
    input logic clk,
    input logic rst_n,
    rv_if.sink write_req,
    rv_if.source write_rsp,
    rv_if.source target_write_req,
    rv_if.source mesh_req_tx,
    rv_if.sink mesh_req_rx,
    rv_if.source mesh_rsp_tx,
    rv_if.sink mesh_rsp_rx
);
    localparam int COORD_BITS = X_BITS + Y_BITS;
    localparam int LOCAL_BITS = ADDR_WIDTH - COORD_BITS;
    localparam int PACKET_WIDTH = DATA_WIDTH + COORD_BITS;

    logic outgoing_busy;
    logic req_pending;
    logic [ADDR_WIDTH-1:0] out_addr;
    logic [DATA_WIDTH-1:0] out_data;
    logic [TAG_WIDTH-1:0] out_tag;
    logic [EPOCH_WIDTH-1:0] out_epoch;
    logic ack_pending;

    typedef enum logic [1:0] {RX_IDLE, RX_WRITE, RX_ACK} rx_state_t;
    rx_state_t rx_state;
    logic [ADDR_WIDTH-1:0] in_addr;
    logic [DATA_WIDTH-1:0] in_data;
    logic [COORD_BITS-1:0] in_source;
    logic [TAG_WIDTH-1:0] in_tag;
    logic [EPOCH_WIDTH-1:0] in_epoch;

    // Capture before injection: upstream may release its payload immediately.
    assign write_req.ready = rst_n && !outgoing_busy;
    assign mesh_req_tx.valid = rst_n && req_pending;
    assign mesh_req_tx.addr = out_addr;
    assign mesh_req_tx.data = {X, Y, out_data};
    assign mesh_req_tx.tag = out_tag;
    assign mesh_req_tx.epoch = out_epoch;

    // ACK includes the original request address/tag/epoch. Zero data = success.
    assign mesh_rsp_rx.ready = rst_n && outgoing_busy && !req_pending && !ack_pending;
    assign write_rsp.valid = rst_n && ack_pending;
    assign write_rsp.addr = out_addr;
    assign write_rsp.data = '0;
    assign write_rsp.tag = out_tag;
    assign write_rsp.epoch = out_epoch;

    assign mesh_req_rx.ready = rst_n && rx_state == RX_IDLE;
    assign target_write_req.valid = rst_n && rx_state == RX_WRITE;
    assign target_write_req.addr = {{COORD_BITS{1'b0}}, in_addr[LOCAL_BITS-1:0]};
    assign target_write_req.data = in_data;
    assign target_write_req.tag = in_tag;
    assign target_write_req.epoch = in_epoch;

    // The ACK routes to the source; its low address bits retain the offset.
    assign mesh_rsp_tx.valid = rst_n && rx_state == RX_ACK;
    assign mesh_rsp_tx.addr = {in_source, in_addr[LOCAL_BITS-1:0]};
    assign mesh_rsp_tx.data = '0;
    assign mesh_rsp_tx.tag = in_tag;
    assign mesh_rsp_tx.epoch = in_epoch;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            outgoing_busy <= 1'b0;
            req_pending <= 1'b0;
            ack_pending <= 1'b0;
            rx_state <= RX_IDLE;
            out_addr <= '0;
            out_data <= '0;
            out_tag <= '0;
            out_epoch <= '0;
            in_addr <= '0;
            in_data <= '0;
            in_source <= '0;
            in_tag <= '0;
            in_epoch <= '0;
        end else begin
            if (write_req.valid && write_req.ready) begin
                outgoing_busy <= 1'b1;
                req_pending <= 1'b1;
                out_addr <= write_req.addr;
                out_data <= write_req.data;
                out_tag <= write_req.tag;
                out_epoch <= write_req.epoch;
            end
            if (mesh_req_tx.valid && mesh_req_tx.ready)
                req_pending <= 1'b0;
            if (mesh_rsp_rx.valid && mesh_rsp_rx.ready)
                ack_pending <= 1'b1;
            if (write_rsp.valid && write_rsp.ready) begin
                ack_pending <= 1'b0;
                outgoing_busy <= 1'b0;
            end
            case (rx_state)
                RX_IDLE: if (mesh_req_rx.valid && mesh_req_rx.ready) begin
                    in_addr <= mesh_req_rx.addr;
                    in_data <= mesh_req_rx.data[DATA_WIDTH-1:0];
                    in_source <= mesh_req_rx.data[DATA_WIDTH +: COORD_BITS];
                    in_tag <= mesh_req_rx.tag;
                    in_epoch <= mesh_req_rx.epoch;
                    rx_state <= RX_WRITE;
                end
                RX_WRITE: if (target_write_req.valid && target_write_req.ready)
                    rx_state <= RX_ACK;
                RX_ACK: if (mesh_rsp_tx.valid && mesh_rsp_tx.ready)
                    rx_state <= RX_IDLE;
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // Detect incompatible wiring and unsolicited/misrouted acknowledgements.
    // synthesis translate_off
    initial begin
        if (X_BITS < 1 || Y_BITS < 1 || LOCAL_BITS < 1)
            $fatal(1, "mesh_write_ni: invalid coordinate/address widths");
        if ($bits(mesh_req_tx.data) != PACKET_WIDTH ||
            $bits(mesh_req_rx.data) != PACKET_WIDTH ||
            $bits(mesh_rsp_tx.data) != PACKET_WIDTH ||
            $bits(mesh_rsp_rx.data) != PACKET_WIDTH)
            $fatal(1, "mesh_write_ni: mesh DATA_WIDTH must include source coordinates");
    end
    always @(posedge clk) if (rst_n && mesh_rsp_rx.valid && mesh_rsp_rx.ready) begin
        assert (mesh_rsp_rx.addr == {X, Y, out_addr[LOCAL_BITS-1:0]} &&
                mesh_rsp_rx.tag == out_tag && mesh_rsp_rx.epoch == out_epoch)
            else $fatal(1, "mesh_write_ni: ACK identity mismatch");
    end
    // synthesis translate_on
endmodule
