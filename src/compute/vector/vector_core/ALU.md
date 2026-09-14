# Vector ALU contract and verification

`vector_alu.sv` declares `vector_alu`. The unfinished parent `vector_core.sv`
declares `vector_core`; connect the ALU when implementing that wrapper.

Operands use signed int8 two's complement. Ports remain bit vectors for
compatibility; signed comparisons and arithmetic right shift cast explicitly.

| Opcode | Operation | Result |
| --- | --- | --- |
| 0 / 1 / 2 | A+B / A-B / A*B | Low 8 bits (wrap, not saturation) |
| 3 / 4 / 5 | AND / OR / XOR | Bitwise A and B |
| 6 | Left shift | A shifted by unsigned B, zero fill |
| 7 | Arithmetic right shift | Signed A shifted by unsigned B, sign fill |
| 8 / 9 | MAX / MIN | Signed comparison of A and B |
| 10 / 11 | EXP / SQRT | Integer LUT; select A for lane_sel=0, B for 1 |
| 12..31 | Reserved | Zero |

Shift counts >=8 produce zero for left shift, and zero/-1 according to the
sign of A for right shift. Unary rounding/domain behavior is specified in LUT.md.

The ALU has a registered output and one skid entry, supporting one accepted
vector and one consumed vector each clock in steady state. Producers must hold
valid, opcode, lane_sel and all operands until ready. Responses remain stable
under backpressure. Active-low synchronous reset discards both buffered vectors;
valid/ready observed on a reset edge must not be treated as a transaction.

Run `src/tb/compute/vector/run_alu.sh` from the project root (Verilator required).
The scoreboard tests 1/8/16 lanes. Each lane exhausts every 256x256 input pair
for binary opcodes 0..9, all 256 inputs on both operand selections for EXP/SQRT,
and reserved opcodes. It additionally checks 5,000 randomized transactions,
input gaps, full buffers, simultaneous input/output, sustained one-vector-per-
clock throughput, output stability, reset flushing and recovery. Expected
results are computed independently of the RTL datapath and LUT tables.

The original unsigned MAX/MIN and logical right shift fail the signed reference
(e.g. MAX(-1,1) returned -1; MIN(-128,127) returned 127; -128>>1 returned 64).
These are corrected to signed comparisons and arithmetic right shift.
