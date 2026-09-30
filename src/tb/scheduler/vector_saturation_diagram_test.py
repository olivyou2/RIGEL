"""Full-width signed products/accumulation and signed-int8 flush saturation.

Run from the outer RIGEL directory:
    python3 diagram/rigel_test.py \
        --design RIGEL/src/generated/vector_core.diagram.json \
        RIGEL/src/tb/scheduler/vector_saturation_diagram_test.py
"""

from rigel_sim import Sink, Source, reset, wait


def enc(op, *, use_imm=0, rd=0, rs0=0, rs1=0, imm=0):
    return (op << 27) | (use_imm << 26) | (rd << 21) | (rs0 << 16) | (rs1 << 11) | (imm & 0x7FF)


write = Source("vector_main_ixc.write_req[0]")
read = Source("vector_main_ixc.read_req[0]")
read_rsp = Sink("vector_main_ixc.read_rsp[0]")

INSTR_BASE = 0x40000
SCH_BASE = 0x80000
C_BASE = 0xC0000


def lanes(value):
    return int.from_bytes(bytes([value & 0xFF] * 16), "little")


reset()
write.stream([(i * 16, lanes(0)) for i in range(4)])
write.stream([(C_BASE + i * 16, lanes(100)) for i in range(4)])
write.stream([
    (INSTR_BASE + 0x00, enc(11, rs0=1, rs1=2, imm=0)),
    (INSTR_BASE + 0x04, enc(11, rs0=3, rs1=2, imm=1)),
    (INSTR_BASE + 0x08, enc(11, rs0=6, rs1=2, imm=2)),
    (INSTR_BASE + 0x0C, enc(13, rs0=4, rs1=5)),
    (INSTR_BASE + 0x10, enc(0, use_imm=1, rd=4, rs0=4, imm=-64)),
    (INSTR_BASE + 0x14, enc(0, use_imm=1, rd=5, rs0=0, imm=1)),
    (INSTR_BASE + 0x18, enc(13, rs0=4, rs1=5)),
    (INSTR_BASE + 0x1C, enc(12, imm=0)),
    (INSTR_BASE + 0x20, enc(12, imm=1)),
    (INSTR_BASE + 0x24, enc(12, imm=2)),
    (INSTR_BASE + 0x28, enc(14)),
])
write.stream([
    (SCH_BASE + 0x04, 0),
    (SCH_BASE + 0x08, 64),
    (SCH_BASE + 0x0C, 0x40),
    (SCH_BASE + 0x18, 0),
    (SCH_BASE + 0x40, 0x100),
    (SCH_BASE + 0x44, 16),
])

# Four +100*100 products sum to +40000: wider than signed 16 bits.
# The 16-bit EMIT word is MUL opcode 2, acc=1, signed saturation mode=01.
for operand, sat_mode, expected in (
    (100, 1, 127), (-100, 1, -128), (100, 2, 255), (100, 0, 64)
):
    write.stream([(0x40 + i * 16, lanes(operand)) for i in range(4)])
    write.send(addr=SCH_BASE + 0x10, data=(sat_mode << 8) | (1 << 6) | (2 << 1))
    write.send(addr=SCH_BASE + 0x14, data=3)
    write.send(addr=SCH_BASE + 0x80, data=0)
    wait(190)
    read.send(addr=C_BASE + 0x100)
    read_rsp.expect(addr=C_BASE + 0x100, data=lanes(expected), timeout=300)
