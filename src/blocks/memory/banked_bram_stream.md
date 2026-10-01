# Banked BRAM stream

`banked_bram_stream.sv` provides parameterized ready/valid logical read and
write ports over `BANKS` independent true dual-port BRAMs. Each bank has **two
physical ports**, and each port can read or write in a cycle. Therefore each
bank can execute at most two operations per cycle: 2R, 1R+1W, or 2W. Different
banks run in parallel. Each logical input has a two-entry request FIFO, so
`ready` acknowledges enqueueing rather than immediate access to a physical
port. The module round-robins queued clients; producers must hold a request
while `ready=0`. An uncongested stream sustains one beat per clock.
Per-bank arbitration decodes clients in parallel and uses one-hot grants for
the two physical ports. Same-word pairs containing a write are serialized.

Parameters: `BANKS`, `READ_PORTS`, `WRITE_PORTS`, `DATA_WIDTH`,
`WORDS_PER_BANK`, `ADDR_WIDTH`, `TAG_WIDTH`, `EPOCH_WIDTH`, and
`RESPONSE_DEPTH` (default 4). Banks, words per
bank, and data width must be powers of two; port counts must be positive.
`ADDR_WIDTH` is at least the local byte-address width,
`log2(BANKS)+log2(WORDS_PER_BANK)+log2(DATA_WIDTH/8)` (omit the bank bits for
one bank). The low local-address bits have this format:

```
{bank index (local MSBs), word index, byte offset (LSBs)}
```

For example, `BANKS=4`, `WORDS_PER_BANK=1024`, `DATA_WIDTH=128` uses a 16-bit
local address: `[15:14]` selects the bank, `[13:4]` the word, and `[3:0]` the
byte offset. A wider system address may be passed directly: high bits are
ignored for memory selection but preserved in read-response metadata. The
upstream interconnect must route addresses to the correct memory region.

Read responses preserve `addr`, `tag`, and `epoch` and remain stable under
backpressure. Each logical read port may have up to `RESPONSE_DEPTH`
granted requests plus two queued requests. A full response reservation stalls
physical grants until a response is consumed on a later clock; it never makes
input `ready` depend combinationally on response `ready`. An uncongested port
can still issue and receive one read beat per clock. Writes have no response;
acceptance into the request FIFO is `valid && ready`. The response FIFO uses
head/tail pointers and does not reset unused payload storage. Simultaneous accesses to the same
word are allowed only when **both are reads**. Any same-word write/read or
write/write pair is serialized because FPGA collision behavior is not portable.
Byte enables and partial-word writes are not supported.

This primitive is used by `vector_system`. Run the
directed test with:

```sh
verilator --binary --timing -Wno-fatal --top-module banked_bram_stream_tb \
  src/interfaces/rv_if.sv src/blocks/memory/bram_dp.sv \
  src/blocks/memory/banked_bram_stream.sv \
  src/tb/bram/banked_bram_stream_tb.sv
./obj_dir/Vbanked_bram_stream_tb
```
