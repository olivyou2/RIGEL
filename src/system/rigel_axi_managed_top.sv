// Host-facing integration top: data gateway + descriptor AXI-Lite slave + CDMA control master.
module rigel_axi_managed_top #(parameter int WORDS_PER_BANK=512, WRITE_DEPTH=8, QUEUE_DEPTH=4,
    parameter logic [31:0] APERTURE_BASE=32'h80000000, CDMA_BASE=32'h00000000)(
    input logic clk, rst_n,
    output logic [15:0] busy, done, fault,
    input logic [31:0] s_axi_awaddr,s_axi_araddr,
    input logic [7:0] s_axi_awlen,s_axi_arlen,
    input logic [2:0] s_axi_awsize,s_axi_arsize,
    input logic [1:0] s_axi_awburst,s_axi_arburst,
    input logic [3:0] s_axi_awid,s_axi_arid,
    input logic s_axi_awvalid,s_axi_wvalid,s_axi_bready,s_axi_arvalid,s_axi_rready,
    output logic s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid,
    input logic [127:0] s_axi_wdata,
    input logic [15:0] s_axi_wstrb,
    input logic s_axi_wlast,
    output logic [3:0] s_axi_bid,s_axi_rid,
    output logic [1:0] s_axi_bresp,s_axi_rresp,
    output logic [127:0] s_axi_rdata,
    output logic s_axi_rlast,
    output logic [31:0] m_axi_awaddr,m_axi_wdata,m_axi_araddr,
    output logic [2:0] m_axi_awprot,m_axi_arprot,
    output logic [3:0] m_axi_wstrb,
    output logic m_axi_awvalid,m_axi_wvalid,m_axi_bready,m_axi_arvalid,m_axi_rready,
    input logic m_axi_awready,m_axi_wready,m_axi_bvalid,m_axi_arready,m_axi_rvalid,
    input logic [1:0] m_axi_bresp,m_axi_rresp,
    input logic [31:0] m_axi_rdata,
    input logic [31:0] s_task_axi_awaddr,s_task_axi_wdata,s_task_axi_araddr,
    input logic [3:0] s_task_axi_wstrb,
    input logic s_task_axi_awvalid,s_task_axi_wvalid,s_task_axi_bready,s_task_axi_arvalid,s_task_axi_rready,
    output logic s_task_axi_awready,s_task_axi_wready,s_task_axi_bvalid,s_task_axi_arready,s_task_axi_rvalid,
    output logic [1:0] s_task_axi_bresp,s_task_axi_rresp,
    output logic [31:0] s_task_axi_rdata
);
    logic task_valid,task_ready,task_has_dependency,task_has_copy,task_copy_only,submit_error;
    logic [7:0] task_id,task_dependency;
    logic [3:0] task_tile,host_tile,completion_tile;
    logic [31:0] task_pc,task_src,task_dst,task_bytes;
    logic completion_valid,completion_ready,completion_error;
    logic [7:0] completion_id;
    logic [255:0] completed,failed;
    mesh_task_control task_control(.*);
    rigel_axi_scheduled_top #(.WORDS_PER_BANK(WORDS_PER_BANK),.WRITE_DEPTH(WRITE_DEPTH),.QUEUE_DEPTH(QUEUE_DEPTH),
        .APERTURE_BASE(APERTURE_BASE),.CDMA_BASE(CDMA_BASE)) system_core(.*);
endmodule
