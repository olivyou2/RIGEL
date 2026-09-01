module fifo_tb();

    logic clk;
    logic rst_n = 0;

    initial clk = 0;
    always #1 clk = !clk;

    logic [63:0] data_in = 0;
    logic data_in_valid = 0;
    logic data_in_ready;

    logic [63:0] data_out;
    logic data_out_valid;
    logic data_out_ready = 0;

    fifo dut(
        .clk(clk),
        .rst_n(rst_n),

        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .data_in_ready(data_in_ready),

        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready)
    );

    task automatic push_data(input logic [63:0] data);
        data_in = data;
        data_in_valid = 1;
        @(posedge clk);
        @(negedge clk);
        if (data_in_valid && data_in_ready) begin
            $display("[FIFO_TB] %0d pushed", data);
        end else begin
            $display("[FIFO_TB] data push failed");
        end
        data_in_valid = 0;
    endtask

    task automatic pop_data();
        $display("[FIFO_TB] wait for data_out_valid=1 (actual=%0d)", data_out_valid);
        wait(data_out_valid == 1);
        data_out_ready = 1;
        $display("[FIFO_TB] data out = %0d", data_out);
        @(posedge clk);
        @(negedge clk);
        data_out_ready = 0;
    endtask

    initial begin
        #100;
        rst_n = 1;

        for (int i=0; i<5; i++) begin
            push_data(64'(i));
        end

        for (int i=0; i<50; i++) begin
            pop_data();
        end

        repeat (2) @(negedge clk);
        if (data_out_valid !== 1'b0)
            $fatal(1, "data_out_valid asserted while FIFO is empty");

        $finish;
    end

endmodule;
