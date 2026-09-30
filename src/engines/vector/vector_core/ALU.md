# Vector ALU contract and verification

`vector_alu.sv` declares `vector_alu`. The unfinished parent `vector_core.sv`
declares `vector_core`; connect the ALU when implementing that wrapper.

Operands use signed int8 two's complement. The 512-bit input beat is
`{control[127:0], C[127:0], B[127:0], A[127:0]}`. Existing operations use
B/C and ignore A; FMA alone uses all three. Ports remain bit vectors for
compatibility; signed comparisons and arithmetic right shift cast explicitly.

| Opcode | Operation | Result |
| --- | --- | --- |
| 0 / 1 / 2 | B+C / B-C / B*C | Signed 16-bit in vector_system; standalone default wraps to 8 bits |
| 3 / 4 / 5 | AND / OR / XOR | Bitwise B and C |
| 6 | Left shift | B shifted by unsigned C, zero fill |
| 7 | Arithmetic right shift | Signed B shifted by unsigned C, sign fill |
| 8 / 9 | MAX / MIN | Signed comparison of B and C |
| 10 / 11 | EXP / SQRT | Integer LUT; select B for lane_sel=0, C for 1 |
| 12 | FMA | A+B*C, signed 16-bit in vector_system |
| 13..31 | Reserved | Zero |

Shift counts >=8 produce zero for left shift, and zero/-1 according to the
sign of B for right shift. Unary rounding/domain behavior is specified in LUT.md.

The ALU has a registered output and one skid entry, supporting one accepted
vector and one consumed vector each clock in steady state. Producers must hold
valid, opcode, lane_sel and all operands until ready. Responses remain stable
under backpressure. Active-low synchronous reset discards both buffered vectors;
valid/ready observed on a reset edge must not be treated as a transaction.

In `vector_system`, the ALU uses 16-bit signed result lanes and forwards the
16-bit raw control word alongside the 256-bit lane result to
`vector_accumulate_slot`. Control bit 6 accumulates a beat without writing;
clearing bit 6 flushes the accumulated lanes plus the current beat to
scratchpad C and clears the accumulator. The accumulator uses signed 32-bit
lanes. Control bits 9:8 select the 8-bit flush conversion: 00 wrap, 01 signed
saturation, 10 unsigned saturation; 11 is reserved and currently wraps. Bit 7
is reserved for reduce and has no effect. The standalone ALU default remains
8-bit result lanes for its legacy tests; `vector_system` sets RESULT_WIDTH=16.

Run `src/tb/compute/vector/run_alu.sh` from the project root (Verilator required).
The scoreboard tests 1/8/16 lanes. Each lane exhausts every 256x256 input pair
for binary opcodes 0..9, all 256 inputs on both operand selections for EXP/SQRT,
FMA and reserved opcodes. It additionally checks 5,000 randomized transactions,
input gaps, full buffers, simultaneous input/output, sustained one-vector-per-
clock throughput, output stability, reset flushing and recovery. Expected
results are computed independently of the RTL datapath and LUT tables.

The original unsigned MAX/MIN and logical right shift fail the signed reference
(e.g. MAX(-1,1) returned -1; MIN(-128,127) returned 127; -128>>1 returned 64).
These are corrected to signed comparisons and arithmetic right shift.
