"""Three MUL beats accumulate into one 8-bit result through vector_system.

Run from the outer RIGEL directory:
    python3 diagram/rigel_test.py \
        --design RIGEL/src/generated/vector_core.diagram.json \
        RIGEL/src/tb/scheduler/vector_accumulate_diagram_test.py
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

reset()
zero = int.from_bytes(bytes([0] * 16), "little")
two = int.from_bytes(bytes([2] * 16), "little")
three = int.from_bytes(bytes([3] * 16), "little")
eighteen = int.from_bytes(bytes([18] * 16), "little")

write.stream([(offset, zero) for offset in (0x00, 0x10, 0x20)])
write.stream([(offset, two) for offset in (0x40, 0x50, 0x60)])
write.stream([(C_BASE + offset, three) for offset in (0x00, 0x10, 0x20)])

write.stream([
    (INSTR_BASE + 0x00, enc(11, rs0=1, rs1=2, imm=0)),
    (INSTR_BASE + 0x04, enc(11, rs0=3, rs1=2, imm=1)),
    (INSTR_BASE + 0x08, enc(11, rs0=6, rs1=2, imm=2)),
    (INSTR_BASE + 0x0C, enc(13, rs0=4, rs1=5)),  # two accumulating beats
    (INSTR_BASE + 0x10, enc(0, use_imm=1, rd=4, rs0=4, imm=-64)),
    (INSTR_BASE + 0x14, enc(0, use_imm=1, rd=5, rs0=0, imm=1)),
    (INSTR_BASE + 0x18, enc(13, rs0=4, rs1=5)),  # final beat flushes
    (INSTR_BASE + 0x1C, enc(12, imm=0)),
    (INSTR_BASE + 0x20, enc(12, imm=1)),
    (INSTR_BASE + 0x24, enc(12, imm=2)),
    (INSTR_BASE + 0x28, enc(14)),
])
write.stream([
    (SCH_BASE + 0x04, 0x00),  # A source, ignored by MUL
    (SCH_BASE + 0x08, 48),    # three 16-byte beats
    (SCH_BASE + 0x0C, 0x40),  # B source
    (SCH_BASE + 0x10, (2 << 1) | (1 << 6)),  # MUL, acc=1
    (SCH_BASE + 0x14, 2),     # first EMIT count
    (SCH_BASE + 0x18, 0x00),  # C source
    (SCH_BASE + 0x40, 0x100),
    (SCH_BASE + 0x44, 16),
])
write.send(addr=SCH_BASE + 0x80, data=0)
wait(180)
read.send(addr=C_BASE + 0x100)
read_rsp.expect(addr=C_BASE + 0x100, data=eighteen, timeout=300)
