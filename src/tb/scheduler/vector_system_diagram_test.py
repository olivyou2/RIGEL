"""Diagram RTL smoke test for vector_system's instruction BRAM and scheduler.

Run from the outer RIGEL directory:
    python3 diagram/rigel_test.py \
        --design RIGEL/src/generated/vector_core.diagram.json \
        RIGEL/src/tb/scheduler/vector_system_diagram_test.py
"""

from rigel_sim import Sink, Source, reset, wait


def enc(op, *, use_imm=0, rd=0, rs0=0, rs1=0, imm=0):
    return (op << 27) | (use_imm << 26) | (rd << 21) | (rs0 << 16) | (rs1 << 11) | (imm & 0x7FF)


write = Source("vector_main_ixc.write_req[0]")
read = Source("vector_main_ixc.read_req[0]")
read_rsp = Sink("vector_main_ixc.read_rsp[0]")

INSTR_BASE = 0x40000  # IXC slave 1: 32-bit instruction BRAM
SCH_BASE = 0x80000    # IXC slave 2: scheduler host registers
C_BASE = 0xC0000      # IXC slave 3: C input and result scratchpad

addi = enc(0, use_imm=1, rd=1, rs0=0, imm=7)
halt = enc(14)
illegal = enc(31)

reset()

# Consecutive 32-bit instructions must occupy distinct BRAM addresses.
write.stream([
    (INSTR_BASE + 0, addi),
    (INSTR_BASE + 4, halt),
    (INSTR_BASE + 8, illegal),
])
for offset, instruction in ((0, addi), (4, halt), (8, illegal)):
    read.send(addr=INSTR_BASE + offset)
    read_rsp.expect(addr=INSTR_BASE + offset, data=instruction)

# Start at PC=0. If the 32-bit address stride or HALT decode is wrong,
# the following scheduler write will time out because write_req.ready is low.
write.send(addr=SCH_BASE + 0x00, data=3)  # r0 = 3
write.send(addr=SCH_BASE + 0x80, data=0)  # FIRE PC=0
wait(80)
write.send(addr=SCH_BASE + 0x08, data=9, timeout=200)  # r2: scheduler is idle again

# All three DMA channels fire. ADD uses B/C and ignores A; FMA uses A+B*C.
operand_a = int.from_bytes(bytes([1] * 16), "little")
operand_b = int.from_bytes(bytes([2] * 16), "little")
operand_c = int.from_bytes(bytes([3] * 16), "little")
expected_add = int.from_bytes(bytes([5] * 16), "little")
expected_fma = int.from_bytes(bytes([7] * 16), "little")
write.stream([(0x00, operand_a), (0x10, operand_b), (C_BASE, operand_c)])
write.stream([
    (INSTR_BASE + 0x20, enc(11, rs0=1, rs1=2, imm=0)),  # CPY DMA0
    (INSTR_BASE + 0x24, enc(11, rs0=3, rs1=2, imm=1)),  # CPY DMA1
    (INSTR_BASE + 0x28, enc(11, rs0=6, rs1=2, imm=2)),  # CPY DMA2
    (INSTR_BASE + 0x2C, enc(13, rs0=4, rs1=5)),         # EMIT control
    (INSTR_BASE + 0x30, enc(12, imm=0)),                # WAIT DMA0
    (INSTR_BASE + 0x34, enc(12, imm=1)),                # WAIT DMA1
    (INSTR_BASE + 0x38, enc(12, imm=2)),                # WAIT DMA2
    (INSTR_BASE + 0x3C, halt),
])
write.stream([
    (SCH_BASE + 0x04, 0x00),  # r1: DMA0 source
    (SCH_BASE + 0x08, 16),    # r2: byte length
    (SCH_BASE + 0x0C, 0x10),  # r3: DMA1 source
    (SCH_BASE + 0x10, 0),     # r4: vector ADD opcode
    (SCH_BASE + 0x14, 1),     # r5: one control word
    (SCH_BASE + 0x18, 0),     # r6: DMA2 source, local to C scratchpad
    (SCH_BASE + 0x40, 0x20),  # OUTPUT_BASE
    (SCH_BASE + 0x44, 16),    # OUTPUT_STEP
])
write.send(addr=SCH_BASE + 0x80, data=0x20)
wait(150)
read.send(addr=C_BASE + 0x20)
read_rsp.expect(addr=C_BASE + 0x20, data=expected_add, timeout=200)

write.send(addr=SCH_BASE + 0x10, data=12 << 1)  # raw control: FMA opcode
write.send(addr=SCH_BASE + 0x40, data=0x30)
write.send(addr=SCH_BASE + 0x80, data=0x20)
wait(150)
read.send(addr=C_BASE + 0x30)
read_rsp.expect(addr=C_BASE + 0x30, data=expected_fma, timeout=200)
