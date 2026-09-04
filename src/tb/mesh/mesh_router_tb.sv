module mesh_router_tb ();

  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 64;
  localparam int X_BITS = 2;
  localparam int Y_BITS = 2;
  localparam logic [X_BITS-1:0] ROUTER_X = 1;
  localparam logic [Y_BITS-1:0] ROUTER_Y = 2;

  localparam int NORTH = 0;
  localparam int WEST  = 1;
  localparam int LOCAL = 2;

  localparam int EAST  = 0;
  localparam int SOUTH = 1;

  logic clk;
  logic rst_n;

  logic [ADDR_WIDTH-1:0] north_addr_in;
  logic [DATA_WIDTH-1:0] north_data_in;
  logic                  north_data_valid;
  logic                  north_data_ready;

  logic [ADDR_WIDTH-1:0] west_addr_in;
  logic [DATA_WIDTH-1:0] west_data_in;
  logic                  west_data_valid;
  logic                  west_data_ready;

  logic [ADDR_WIDTH-1:0] east_addr_out;
  logic [DATA_WIDTH-1:0] east_data_out;
  logic                  east_data_valid;
  logic                  east_data_ready;

  logic [ADDR_WIDTH-1:0] south_addr_out;
  logic [DATA_WIDTH-1:0] south_data_out;
  logic                  south_data_valid;
  logic                  south_data_ready;

  logic [ADDR_WIDTH-1:0] local_addr_in;
  logic [DATA_WIDTH-1:0] local_data_in;
  logic                  local_data_in_valid;
  logic                  local_data_in_ready;

  logic [ADDR_WIDTH-1:0] local_addr_out;
  logic [DATA_WIDTH-1:0] local_data_out;
  logic                  local_data_out_valid;
  logic                  local_data_out_ready;

  int pass_count;

  mesh_router #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .X_BITS    (X_BITS),
      .Y_BITS    (Y_BITS),
      .X         (ROUTER_X),
      .Y         (ROUTER_Y)
  ) dut (
      .clk                 (clk),
      .rst_n               (rst_n),
      .north_addr_in       (north_addr_in),
      .north_data_in       (north_data_in),
      .north_data_valid    (north_data_valid),
      .north_data_ready    (north_data_ready),
      .west_addr_in        (west_addr_in),
      .west_data_in        (west_data_in),
      .west_data_valid     (west_data_valid),
      .west_data_ready     (west_data_ready),
      .east_addr_out       (east_addr_out),
      .east_data_out       (east_data_out),
      .east_data_valid     (east_data_valid),
      .east_data_ready     (east_data_ready),
      .south_addr_out      (south_addr_out),
      .south_data_out      (south_data_out),
      .south_data_valid    (south_data_valid),
      .south_data_ready    (south_data_ready),
      .local_addr_in       (local_addr_in),
      .local_data_in       (local_data_in),
      .local_data_in_valid (local_data_in_valid),
      .local_data_in_ready (local_data_in_ready),
      .local_addr_out      (local_addr_out),
      .local_data_out      (local_data_out),
      .local_data_out_valid(local_data_out_valid),
      .local_data_out_ready(local_data_out_ready)
  );

  initial clk = 0;
  always #1 clk = !clk;

  function automatic logic [ADDR_WIDTH-1:0] make_addr(
      input logic [X_BITS-1:0] x,
      input logic [Y_BITS-1:0] y,
      input logic [ADDR_WIDTH-X_BITS-Y_BITS-1:0] offset
  );
    make_addr = {x, y, offset};
  endfunction

  task automatic reset_dut;
    @(negedge clk);
    rst_n = 0;
    north_data_valid = 0;
    west_data_valid = 0;
    local_data_in_valid = 0;
    east_data_ready = 1;
    south_data_ready = 1;
    local_data_out_ready = 1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);
  endtask

  task automatic send_packet(
      input int source,
      input logic [ADDR_WIDTH-1:0] addr,
      input logic [DATA_WIDTH-1:0] data
  );
    @(negedge clk);
    case (source)
      NORTH: begin
        north_addr_in = addr;
        north_data_in = data;
        north_data_valid = 1;
        do @(posedge clk); while (north_data_ready !== 1'b1);
        @(negedge clk);
        north_data_valid = 0;
      end
      WEST: begin
        west_addr_in = addr;
        west_data_in = data;
        west_data_valid = 1;
        do @(posedge clk); while (west_data_ready !== 1'b1);
        @(negedge clk);
        west_data_valid = 0;
      end
      LOCAL: begin
        local_addr_in = addr;
        local_data_in = data;
        local_data_in_valid = 1;
        do @(posedge clk); while (local_data_in_ready !== 1'b1);
        @(negedge clk);
        local_data_in_valid = 0;
      end
      default: $fatal(1, "Unknown source %0d", source);
    endcase
  endtask

  task automatic expect_packet(
      input int destination,
      input logic [ADDR_WIDTH-1:0] expected_addr,
      input logic [DATA_WIDTH-1:0] expected_data
  );
    case (destination)
      EAST: begin
        do @(negedge clk); while (east_data_valid !== 1'b1);
        if (east_addr_out !== expected_addr || east_data_out !== expected_data)
          $fatal(1, "EAST mismatch: addr=%h data=%h, expected addr=%h data=%h",
                 east_addr_out, east_data_out, expected_addr, expected_data);
      end
      SOUTH: begin
        do @(negedge clk); while (south_data_valid !== 1'b1);
        if (south_addr_out !== expected_addr || south_data_out !== expected_data)
          $fatal(1, "SOUTH mismatch: addr=%h data=%h, expected addr=%h data=%h",
                 south_addr_out, south_data_out, expected_addr, expected_data);
      end
      LOCAL: begin
        do @(negedge clk); while (local_data_out_valid !== 1'b1);
        if (local_addr_out !== expected_addr || local_data_out !== expected_data)
          $fatal(1, "LOCAL mismatch: addr=%h data=%h, expected addr=%h data=%h",
                 local_addr_out, local_data_out, expected_addr, expected_data);
      end
      default: $fatal(1, "Unknown destination %0d", destination);
    endcase

    pass_count = pass_count + 1;
    @(posedge clk);
  endtask

  task automatic check_route(
      input int source,
      input int destination,
      input logic [ADDR_WIDTH-1:0] addr,
      input logic [DATA_WIDTH-1:0] data
  );
    $display("[MESH_ROUTER_TB] route source=%0d destination=%0d data=%h", source, destination, data);
    fork
      send_packet(source, addr, data);
      expect_packet(destination, addr, data);
    join
  endtask

  logic collect_east;
  int east_count;
  logic [DATA_WIDTH-1:0] east_seen [0:2];

  always @(posedge clk) begin
    if (collect_east && east_data_valid && east_data_ready) begin
      if (east_count >= 3)
        $fatal(1, "EAST produced more packets than expected");
      east_seen[east_count] = east_data_out;
      east_count = east_count + 1;
    end
  end

  task automatic check_east_contention;
    logic found_north;
    logic found_west;
    logic found_local;
    logic [ADDR_WIDTH-1:0] addr;

    $display("[MESH_ROUTER_TB] east contention");
    reset_dut();
    addr = make_addr(2, 3, 28'h1234567);
    east_count = 0;
    collect_east = 1;

    fork
      send_packet(NORTH, addr, 64'h1000_0000_0000_0001);
      send_packet(WEST,  addr, 64'h2000_0000_0000_0002);
      send_packet(LOCAL, addr, 64'h3000_0000_0000_0003);
    join

    while (east_count < 3) @(posedge clk);
    @(negedge clk);
    collect_east = 0;

    found_north = 0;
    found_west = 0;
    found_local = 0;
    for (int i = 0; i < 3; i++) begin
      if (east_seen[i] == 64'h1000_0000_0000_0001) found_north = 1;
      if (east_seen[i] == 64'h2000_0000_0000_0002) found_west = 1;
      if (east_seen[i] == 64'h3000_0000_0000_0003) found_local = 1;
    end

    if (!found_north || !found_west || !found_local)
      $fatal(1, "Contention test lost or duplicated a packet");

    pass_count = pass_count + 1;
  endtask

  task automatic check_backpressure;
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] data;

    $display("[MESH_ROUTER_TB] east backpressure");
    reset_dut();
    addr = make_addr(2, ROUTER_Y, 28'h0badc0d);
    data = 64'hfeed_face_dead_beef;
    east_data_ready = 0;

    send_packet(NORTH, addr, data);
    do @(negedge clk); while (east_data_valid !== 1'b1);

    repeat (4) begin
      @(posedge clk);
      if (east_data_valid !== 1'b1 || east_addr_out !== addr || east_data_out !== data)
        $fatal(1, "EAST output changed while backpressured");
    end

    @(negedge clk);
    east_data_ready = 1;
    @(posedge clk);
    @(negedge clk);
    if (east_data_valid !== 1'b0)
      $fatal(1, "EAST valid did not clear after handshake");

    pass_count = pass_count + 1;
  endtask

  initial begin
    rst_n = 0;
    north_addr_in = 0;
    north_data_in = 0;
    north_data_valid = 0;
    west_addr_in = 0;
    west_data_in = 0;
    west_data_valid = 0;
    local_addr_in = 0;
    local_data_in = 0;
    local_data_in_valid = 0;
    east_data_ready = 1;
    south_data_ready = 1;
    local_data_out_ready = 1;
    collect_east = 0;
    east_count = 0;
    pass_count = 0;

    reset_dut();

    // X routing has priority when both destination coordinates differ.
    check_route(NORTH, EAST,  make_addr(2, 3, 28'h0000011), 64'h0000_0000_0000_0011);
    check_route(NORTH, SOUTH, make_addr(ROUTER_X, 3, 28'h0000012), 64'h0000_0000_0000_0012);
    check_route(NORTH, LOCAL, make_addr(ROUTER_X, ROUTER_Y, 28'h0000013), 64'h0000_0000_0000_0013);

    check_route(WEST, EAST,  make_addr(2, ROUTER_Y, 28'h0000021), 64'h0000_0000_0000_0021);
    check_route(WEST, SOUTH, make_addr(ROUTER_X, 3, 28'h0000022), 64'h0000_0000_0000_0022);
    check_route(WEST, LOCAL, make_addr(ROUTER_X, ROUTER_Y, 28'h0000023), 64'h0000_0000_0000_0023);

    check_route(LOCAL, EAST,  make_addr(2, ROUTER_Y, 28'h0000031), 64'h0000_0000_0000_0031);
    check_route(LOCAL, SOUTH, make_addr(ROUTER_X, 3, 28'h0000032), 64'h0000_0000_0000_0032);
    check_route(LOCAL, LOCAL, make_addr(ROUTER_X, ROUTER_Y, 28'h0000033), 64'h0000_0000_0000_0033);

    check_east_contention();
    check_backpressure();

    $display("[MESH_ROUTER_TB] PASS (%0d checks)", pass_count);
    $finish;
  end

  initial begin
    #2000;
    $fatal(1, "[MESH_ROUTER_TB] timeout");
  end

endmodule
