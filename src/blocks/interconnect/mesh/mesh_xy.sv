// Packet address: [31:30] X, [29:28] Y, [27:0] endpoint offset.
module mesh_xy #(
    parameter int DATA_WIDTH=133, WIDTH=4, HEIGHT=4
)(input logic clk, rst_n,
  rv_if.sink in_ch[WIDTH*HEIGHT], rv_if.source out_ch[WIDTH*HEIGHT]);
    for(genvar y=0;y<HEIGHT;y++) begin : rows
        for(genvar x=0;x<WIDTH;x++) begin : cols
            localparam int NODE=x+y*WIDTH;
            rv_if #(.DATA_WIDTH(DATA_WIDTH)) inputs[5](), outputs[5]();
            mesh_xy_router #(.DATA_WIDTH(DATA_WIDTH),.X(x),.Y(y)) router(
                .clk(clk),.rst_n(rst_n),.in_ch(inputs),.out_ch(outputs));
            assign inputs[0].valid=in_ch[NODE].valid;
            assign inputs[0].addr=in_ch[NODE].addr;
            assign inputs[0].data=in_ch[NODE].data;
            assign inputs[0].tag=in_ch[NODE].tag;
            assign inputs[0].epoch=in_ch[NODE].epoch;
            assign in_ch[NODE].ready=inputs[0].ready;
            assign out_ch[NODE].valid=outputs[0].valid;
            assign out_ch[NODE].addr=outputs[0].addr;
            assign out_ch[NODE].data=outputs[0].data;
            assign out_ch[NODE].tag=outputs[0].tag;
            assign out_ch[NODE].epoch=outputs[0].epoch;
            assign outputs[0].ready=out_ch[NODE].ready;
            for(genvar p=1;p<5;p++) begin : links
                if((p==1 && x+1<WIDTH)||(p==2 && x>0)||
                   (p==3 && y+1<HEIGHT)||(p==4 && y>0)) begin : connected
                    localparam int NX=p==1 ? x+1 : p==2 ? x-1 : x;
                    localparam int NY=p==3 ? y+1 : p==4 ? y-1 : y;
                    localparam int OPP=p==1 ? 2 : p==2 ? 1 : p==3 ? 4 : 3;
                    assign inputs[p].valid=rows[NY].cols[NX].outputs[OPP].valid;
                    assign inputs[p].addr=rows[NY].cols[NX].outputs[OPP].addr;
                    assign inputs[p].data=rows[NY].cols[NX].outputs[OPP].data;
                    assign inputs[p].tag=rows[NY].cols[NX].outputs[OPP].tag;
                    assign inputs[p].epoch=rows[NY].cols[NX].outputs[OPP].epoch;
                    assign outputs[p].ready=rows[NY].cols[NX].inputs[OPP].ready;
                end else begin : boundary
                    assign inputs[p].valid=0;
                    assign inputs[p].addr=0;
                    assign inputs[p].data=0;
                    assign inputs[p].tag=0;
                    assign inputs[p].epoch=0;
                    assign outputs[p].ready=0;
                end
            end
        end
    end
    initial if(WIDTH<1 || WIDTH>4 || HEIGHT<1 || HEIGHT>4)
        $fatal(1,"mesh_xy supports 1..4 tiles per dimension");
endmodule
