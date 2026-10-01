"""Exercise all three banked memories through the vector_system diagram.

Run from the outer RIGEL directory:
    python3 diagram/rigel_test.py --design RIGEL/src/generated/vector_core.diagram.json \
        RIGEL/src/tb/scheduler/vector_system_banked_diagram_test.py
"""

from rigel_sim import Sink, Source, reset, wait


def enc(op, *, rs0=0, rs1=0, imm=0):
    return (op << 27) | (rs0 << 16) | (rs1 << 11) | imm


write = Source("vector_main_ixc.write_req[0]")
read = Source("vector_main_ixc.read_req[0]")
rsp = Sink("vector_main_ixc.read_rsp[0]")
INSTR = 0x40000
SCH = 0x80000
C = 0xC0000

reset()

# A/C banks change every 0x1000 bytes; instruction banks every 0x400.
# Distinct data in each bank catches accidental aliasing across bank MSBs.
for bank in range(4):
    a_addr = bank * 0x1000
    c_addr = C + bank * 0x1000
    i_addr = INSTR + bank * 0x400
    write.send(addr=a_addr, data=0x11 + bank)
    write.send(addr=c_addr, data=0x21 + bank)
    write.send(addr=i_addr, data=enc(14) + bank)

for bank in range(4):
    read.send(addr=bank * 0x1000)
    rsp.expect(addr=bank * 0x1000, data=0x11 + bank)
    read.send(addr=C + bank * 0x1000)
    rsp.expect(addr=C + bank * 0x1000, data=0x21 + bank)
    read.send(addr=INSTR + bank * 0x400)
    rsp.expect(addr=INSTR + bank * 0x400, data=enc(14) + bank)

# Fetch instructions from instruction bank 1. DMA0 reads A bank 1, DMA1
# reads A bank 2, DMA2 reads C bank 1, and the result lands in C bank 2.
a = int.from_bytes(bytes([1] * 16), "little")
b = int.from_bytes(bytes([2] * 16), "little")
c = int.from_bytes(bytes([3] * 16), "little")
expected = int.from_bytes(bytes([7] * 16), "little")  # FMA: A + B*C
write.stream([(0x1010, a), (0x2010, b), (C + 0x1010, c)])
write.stream([
    (INSTR + 0x420, enc(11, rs0=1, rs1=2, imm=0)),
    (INSTR + 0x424, enc(11, rs0=3, rs1=2, imm=1)),
    (INSTR + 0x428, enc(11, rs0=6, rs1=2, imm=2)),
    (INSTR + 0x42C, enc(13, rs0=4, rs1=5)),
    (INSTR + 0x430, enc(12, imm=0)),
    (INSTR + 0x434, enc(12, imm=1)),
    (INSTR + 0x438, enc(12, imm=2)),
    (INSTR + 0x43C, enc(14)),
])
write.stream([
    (SCH + 0x04, 0x1010), (SCH + 0x08, 16),
    (SCH + 0x0C, 0x2010), (SCH + 0x10, 12 << 1),
    (SCH + 0x14, 1), (SCH + 0x18, 0x1010),
    (SCH + 0x40, 0x2020), (SCH + 0x44, 16),
])
write.send(addr=SCH + 0x80, data=0x420)
wait(150)
read.send(addr=C + 0x2020)
rsp.expect(addr=C + 0x2020, data=expected, timeout=200)
