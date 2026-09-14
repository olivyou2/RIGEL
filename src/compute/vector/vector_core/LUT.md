# Integer exp/sqrt LUTs

`vector_exp` and `vector_sqrt` interpret each 8-bit lane as a signed two's
complement integer (-128 through 127), with no fractional scaling. Existing
bit-vector ports, lane parallelism and combinational latency are preserved.
The parent ALU supplies the output registers and ready/valid handling.

- exp: `min(127, floor(exp(x)))`. Negative inputs produce 0; inputs 0..4
  produce 1, 2, 7, 20, 54; inputs 5..127 saturate to 127.
- sqrt: `floor(sqrt(x))` for nonnegative x. Negative inputs produce 0,
  since this interface has no domain-error output.
- Only `DATA_WIDTH=8` is supported; other widths fail explicitly. `LANE_SIZE`
  remains configurable and must be positive.

The tables contain only integer constants and combinational selection; no
runtime exponential/square-root operator, multiplier or real math is used.
Synthesis may map the case tables to logic rather than a memory macro.

This unscaled integer exp loses all fractional values for negative arguments.
Softmax using x-max(x) will therefore retain only maximum entries; a useful
softmax implementation needs a separately specified fixed-point/quantized scale.

Run `src/tb/compute/vector/run_lut.sh` from the project directory. It checks
all 256 input patterns on every lane for 1/8/16 lanes using independent math
references, and tests ALU opcode/operand selection and stalled response stability.
It also lints the implemented ALU and its LUT dependencies. It selects the implemented `vector_alu` and its dependencies explicitly;
the parent `vector_core.sv` remains an unfinished wrapper.
