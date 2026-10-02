// Reserve completion slots at acceptance; acknowledge AFTER physical BRAM writes.
// Metadata remains in client order. Registered occupancy isolates ready paths.
module banked_bram_with_rsp #(
    parameter int BANKS=2, READ_PORTS=2, WRITE_PORTS=2, DATA_WIDTH=128,
    WORDS_PER_BANK=512, ADDR_WIDTH=32, ACK_DEPTH=8
)(input logic clk, rst_n, rv_if.sink read_req[READ_PORTS],
  rv_if.source read_rsp[READ_PORTS], rv_if.sink write_req[WRITE_PORTS],
  rv_if.source write_rsp[WRITE_PORTS]);
    localparam int PTR=$clog2(ACK_DEPTH), CNT=$clog2(ACK_DEPTH+1);
    rv_if #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH)) writes[WRITE_PORTS]();
    logic [WRITE_PORTS-1:0] committed;
    banked_bram_stream_core #(.BANKS(BANKS),.READ_PORTS(READ_PORTS),.WRITE_PORTS(WRITE_PORTS),
        .DATA_WIDTH(DATA_WIDTH),.WORDS_PER_BANK(WORDS_PER_BANK),.ADDR_WIDTH(ADDR_WIDTH)) core(
        .clk(clk),.rst_n(rst_n),.read_req(read_req),.read_rsp(read_rsp),
        .write_req(writes),.write_commit(committed));
    for(genvar p=0;p<WRITE_PORTS;p++) begin : clients
        logic [PTR-1:0] head, tail;
        logic [CNT-1:0] reserved, available;
        logic [ADDR_WIDTH-1:0] addr[ACK_DEPTH];
        logic [3:0] tag[ACK_DEPTH], epoch[ACK_DEPTH];
        wire push=write_req[p].valid && write_req[p].ready;
        wire pop=write_rsp[p].valid && write_rsp[p].ready;
        assign writes[p].valid=rst_n && write_req[p].valid && reserved<CNT'(ACK_DEPTH);
        assign writes[p].addr=write_req[p].addr;
        assign writes[p].data=write_req[p].data;
        assign writes[p].tag=write_req[p].tag;
        assign writes[p].epoch=write_req[p].epoch;
        assign write_req[p].ready=rst_n && reserved<CNT'(ACK_DEPTH) && writes[p].ready;
        assign write_rsp[p].valid=rst_n && available!=0;
        assign write_rsp[p].addr=addr[head];
        assign write_rsp[p].data=0;
        assign write_rsp[p].tag=tag[head];
        assign write_rsp[p].epoch=epoch[head];
        always_ff @(posedge clk) begin
            if(!rst_n) begin head<=0; tail<=0; reserved<=0; available<=0; end
            else begin
                if(push) begin
                    addr[tail]<=write_req[p].addr; tag[tail]<=write_req[p].tag;
                    epoch[tail]<=write_req[p].epoch; tail<=tail+1'b1;
                end
                if(pop) head<=head+1'b1;
                case({push,pop})
                    2'b10:reserved<=reserved+1'b1;
                    2'b01:reserved<=reserved-1'b1;
                    default:;
                endcase
                case({committed[p],pop})
                    2'b10:available<=available+1'b1;
                    2'b01:available<=available-1'b1;
                    default:;
                endcase
            end
        end
    end
    initial if(ACK_DEPTH<4 || (ACK_DEPTH & (ACK_DEPTH-1))!=0)
        $fatal(1,"banked_bram_with_rsp ACK_DEPTH must be a power of two >=4");
endmodule
