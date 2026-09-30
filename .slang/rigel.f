-I src

src/interfaces/rv_if.sv
src/interfaces/dma_ctrl_if.sv

src/common/rv/skid.sv
src/common/rv/fifo.sv
src/common/rv/handshake_join.sv
src/common/rv/handshake_addr_join.sv
src/common/rv/handshake_distribute.sv

src/common/arbitration/arbiter.sv
src/common/arbitration/arbiter_skid.sv

src/blocks/memory/bram.sv
src/blocks/memory/bram_dp.sv
src/blocks/memory/bram_stream.sv
src/blocks/memory/bram_dp_stream.sv
src/blocks/memory/bram_arbiter.sv

src/blocks/interconnect/ixc/ixc_rr_arbiter.sv
src/blocks/interconnect/ixc/ixc_control.sv
src/blocks/interconnect/ixc/ixc_read.sv
src/blocks/interconnect/ixc/ixc_general_selector.sv
src/blocks/interconnect/ixc/ixc.sv
src/blocks/interconnect/mesh/mesh_router.sv
src/blocks/interconnect/mesh/mesh.sv

src/engines/dma/dma_control.sv
src/engines/dma/dma_src_addr.sv
src/engines/dma/dma_dst_addr.sv
src/engines/dma/dma.sv
src/engines/dma/dma_ixc_control.sv
src/engines/sge/sge_reg_control.sv
src/engines/sge/sge_reg_assemble.sv
src/engines/sge/sge_reg.sv
src/engines/vector/vector_core/vector_exp.sv
src/engines/vector/vector_core/vector_sqrt.sv
src/engines/vector/vector_core/vector_alu.sv
src/engines/vector/vector_core/vector_accumulate_slot.sv
src/engines/vector/vector_core_ixc_sel.sv
src/engines/vector/vector_command_scheduler.sv
src/engines/vector/vector.sv
src/engines/scheduler/schduler_fetch.sv
src/engines/compute/compute_ixc_sel.sv
src/engines/compute/compute.sv

src/generated/vector_accumulate.sv
src/generated/vector_core.sv
src/top.sv

src/tb/utils/skid_tb.sv
src/tb/utils/handshake_join_tb.sv
src/tb/utils/handshake_addr_join_tb.sv
src/tb/utils/handshake_distribute_tb.sv
src/tb/arbiter/arbiter_tb.sv
src/tb/fifo/fifo_tb.sv
src/tb/bram/bram_stream_tb.sv
src/tb/bram/bram_dp_stream_tb.sv
src/tb/ixc/ixc_tb.sv
src/tb/ixc/ixc_bram_tb.sv
src/tb/mesh/mesh_router_tb.sv
src/tb/mesh/mesh_tb.sv
src/tb/compute/dma/dma_addr_src_tb.sv
src/tb/compute/dma/dma_addr_tb.sv
src/tb/compute/dma/dma_tb.sv
src/tb/compute/dma/dma_sge_tb.sv
src/tb/compute/vector/vector_alu_tb.sv
src/tb/compute/vector/vector_lut_tb.sv
src/tb/compute/vector/vector_core_ixc_sel_tb.sv
src/tb/compute/compute_tb.sv
