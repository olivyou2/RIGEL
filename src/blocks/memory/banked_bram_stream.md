# Banked BRAM stream

`banked_bram_stream.sv` provides parameterized ready/valid logical read and
write ports over `BANKS` independent true dual-port BRAMs. Each bank has **two
physical ports**, and each port can read or write in a cycle. Therefore each
bank can accept at most two operations per cycle: 2R, 1R+1W, or 2W. Different
banks run in parallel. The module round-robins contending logical clients;
unaccepted requests must hold their payload while `ready=0`.

Parameters: `BANKS`, `READ_PORTS`, `WRITE_PORTS`, `DATA_WIDTH`,
`WORDS_PER_BANK`, `ADDR_WIDTH`, `TAG_WIDTH`, `EPOCH_WIDTH`, and
`RESPONSE_DEPTH` (default 4). Banks, words per
bank, and data width must be powers of two; port counts must be positive.
`ADDR_WIDTH` is the **local byte-address width**, exactly
`log2(BANKS)+log2(WORDS_PER_BANK)+log2(DATA_WIDTH/8)` (omit the bank bits for
one bank). Addresses have this format:

```
{bank index (MSBs), word index, byte offset (LSBs)}
```

For example, `BANKS=4`, `WORDS_PER_BANK=1024`, `DATA_WIDTH=128` uses a 16-bit
local address: `[15:14]` selects the bank, `[13:4]` the word, and `[3:0]` the
byte offset. A 32-bit system bus should select the memory region and pass its
16-bit local address to this primitive; it does not silently alias unused
upper bits.

Read responses preserve `addr`, `tag`, and `epoch` and remain stable under
backpressure. Each logical read port may have up to `RESPONSE_DEPTH`
outstanding requests, allowing one read beat per clock when uncongested. Writes have
no response; acceptance is `valid && ready`. Simultaneous accesses to the same
word are allowed only when **both are reads**. Any same-word write/read or
write/write pair is serialized because FPGA collision behavior is not portable.
Byte enables and partial-word writes are not supported.

This is a reusable primitive, not yet connected to `vector_system`. Run the
directed test with:

```sh
verilator --binary --timing -Wno-fatal --top-module banked_bram_stream_tb \
  src/interfaces/rv_if.sv src/blocks/memory/bram_dp.sv \
  src/blocks/memory/banked_bram_stream.sv \
  src/tb/bram/banked_bram_stream_tb.sv
./obj_dir/Vbanked_bram_stream_tb
```
