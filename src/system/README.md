# RIGEL 4x4 vector system

## Entry points

- `rigel_mesh_top.sv`: flat-pin FPGA synthesis top with registered host boundaries.
- `rigel_mesh_system.sv`: interface-based integration of 16 vector tiles.
- `files.f`: exact RTL source manifest, paths relative to the inner RIGEL root.
- `../tb/system/run.sh`: strict full-size lint and self-checking simulations.
- `../../synthesis_mesh.tcl`: Vivado synthesis/place/route timing flow.

The existing generated `vector_system` and legacy east/south wraparound `mesh`
remain available. This system uses a hand-maintained integration of the same
scheduler, DMA, vector ALU, accumulator and banked memory primitives. Generated
RTL is not edited. Host integration here is ready/valid; PCIe, AXI and external
DRAM controllers are board-specific work and are not part of this top.

## Architecture

```
Host -> registered IO -> system control -> tile-0 source arbiter
                                             |
                 4x4 request XY mesh (READ_REQ / WRITE_REQ)
                                             |
     [NI -> endpoint decoder -> vector core + A/C/instruction SRAM] x16
                                             |
                 4x4 response XY mesh (READ_RSP / WRITE_ACK)
```

Every tile also has a copy engine connected to its NI source. It can read an
arbitrary tile's vector memory and write another tile's vector memory. Tile 0
shares its source between host and copy engine with per-write round-robin
arbitration and a queued response-owner map. Inbound and outbound NI state is independent, so a tile can
serve remote requests while waiting for its own response.

`WRITE_DEPTH` defaults to 8 and is propagated from `rigel_mesh_top` through the
system, NI, source arbiter and tile endpoints. Powers of two from 1 to 16 are
supported. Each NI reserves up to this many outgoing writes and incoming writes;
reads remain single-outstanding and wait for the local write window to drain.
There is no AXI burst framing or block ACK: every 16-byte write still receives
its own completion. The write window targets one tile at a time; switching to
another tile waits for earlier client ACKs to be consumed.

The copy engine itself retains read -> write -> destination ACK for each beat.
It therefore does not fill the new write window on its own. Streaming host or
future DDR DMA producers can use the window; block-prefetch/overlap in the copy
engine is a separate change. There is no cache coherence.

## Address map

Global address = `{X[1:0], Y[1:0], local_offset[27:0]}`.
Tile index for masks/arrays = `X + 4*Y`. NI removes coordinates for endpoints.
The address carried by the response at the origin is the original global address.

| Tile-local window | Meaning |
|---|---|
| `0x000000` | Vector scratchpad A (two banks, used for A and B operands) |
| `0x040000` | 32-bit instruction SRAM (two banks) |
| `0x080000` | Read: `{fault,done,busy}` in bits 2:0; scheduler write registers |
| `0x080004..0x080044` | Existing scheduler GPR/output registers |
| `0x080080` | Start scheduler: write local instruction PC |
| `0x0c0000` | Vector scratchpad C (operand C and results) |
| `0x100000` | Tile status, bits 5:0 described below |
| `0x100010` | Copy source global byte address (RW) |
| `0x100014` | Copy destination global byte address (RW) |
| `0x100018` | Copy length in bytes (RW) |
| `0x10001c` | Copy START: write exactly 1 |

Default `WORDS_PER_BANK=512`: A and C each contain 16 KiB, instructions contain
4 KiB, for 36 KiB per tile and 576 KiB of logical SRAM across 16 tiles. Actual
FPGA BRAM utilization depends on width/depth packing. Sizes are configurable
with `WORDS_PER_BANK`, a power of two; two banks are retained. Instruction
addresses are 4-byte aligned; vector accesses are full 16-byte aligned beats.
Scheduler launch PC is a local instruction byte offset, not its global address.

Tile status bits: 0 core busy, 1 core done, 2 core fault, 3 copy busy, 4 copy done,
5 copy fault. Top-level `busy[n]` is core OR copy busy; `done[n]` is asserted only
when both are idle and at least one completion flag is set. Completion flags
persist until the corresponding next launch/reset. Top `fault[n]` also includes
invalid tile CSR accesses. Consult the separate core/copy bits for job-specific
status rather than interpreting a stale completion flag as a new job's result.

Global **host-only** control page `0x0ff00000` is intercepted before the gateway;
it is not reachable by copy engines. It does not alias tile memory.

| Global control offset | Access | Meaning |
|---|---|---|
| `+0x00` | R | Registered 16-bit busy mask |
| `+0x04` | R | Registered 16-bit done mask |
| `+0x08` | R | Registered 16-bit fault mask |
| `+0x0c` | R | Active masked launch |
| `+0x10` | RW | Mask of vector cores to launch |
| `+0x14` | RW | Common local instruction PC |
| `+0x18` | W | Write 1 to launch selected cores |
| `+0x1c` | R | All selected jobs have completed |

Load tile inputs, instructions and scheduler registers, consuming each write
ACK. Set launch mask/PC, then write START. START ACK means launch accepted,
not jobs completed. The control unit observes each selected tile become busy
before recognizing its DONE, so repeated launches cannot complete from stale
DONE flags. Mask/PC updates and another launch are rejected while a masked job
is active; launch also rejects selected tiles that are already busy.

For a dependent layer: wait for source core DONE, configure its copy engine,
START the copy, wait for copy DONE without fault, then launch the destination
core. No global cache/fence mechanism is required for this explicit workflow.
Do not update a tile's operand/program memory while its core is running, or
race remote writes with that core's writes to the same addresses.

## Packet and completion contract

Both meshes carry 32-bit address, 133-bit data, 4-bit tag and 4-bit epoch.

- Request data: `{is_write, source_X[1:0], source_Y[1:0], payload[127:0]}`.
- Response data: `{is_write, 4'b0, payload[127:0]}`.
- Successful write response payload is zero; rejected writes return 1.
- Read responses contain data; unsupported reads return zero and latch an
  endpoint fault. There is no separate read error channel in this version;
  software must check fault status/masks and use the valid address map.

NI captures requests and reserves response slots before injection. For writes,
the 4-bit network tag is an allocated slot ID, not the client's original tag.
The original address/tag/epoch remain in the slot until the client consumes its
ACK. Network ACKs may arrive out of order; per-slot completion flags reorder them
into client acceptance order. Duplicate client tags are supported because they
are not used to allocate network IDs. Slots are not reused while an ACK is
unconsumed. The packet layout and beat-level ACK payload are unchanged.

The destination NI queues write requests and request-owner metadata separately
from ACK transmission. Endpoints must return their write responses in acceptance
order. The tile core allocates its own IDs to memory-port writes and reorders
A/C/instruction completions into this order. Simulation assertions check both
network identities and endpoint response ownership/order. Different sources
have independent IDs; the destination associates each reply with the stored
source coordinates rather than assuming network tags are globally unique.

ACK reception uses reserved slots and does not depend on client response ready.
A stalled client response holds its slot; window occupancy bounds request ready.
Source/destination queues and packet launch registers isolate ready propagation.
The source mux retains an owner entry for every host/copy write and routes every
ACK back to that source. Host and tile control-page writes act as barriers: they
wait for earlier forwarded writes to retire and hold later writes until their
control response is consumed. Scheduler register writes likewise wait for older
core writes before execution.

Reads fence writes already accepted by that NI, but independent producers and
host input queues do not establish a global memory ordering rule. Consume write
responses before submitting dependent reads or starts. A host's total accepted
but unconsumed requests may exceed WRITE_DEPTH because its registered input and
output boundary queues add buffering; the NI's actual write window remains
bounded by WRITE_DEPTH.

`banked_bram_with_rsp` reserves ACK metadata slots at request acceptance and
makes ACK available only AFTER the physical BRAM write edge. The posted-write
`banked_bram_stream` now wraps the shared core, retaining its previous external
behavior. Scheduler CSR ACK means register write/launch acceptance. Vector core
DONE waits for scheduler termination, operand DMA idle, and all emitted flush
results to be physically written. HALT with unflushed accumulation reports a
core fault. Programs must match operand/control counts and flush accumulators;
there is no execution timeout/recovery controller beyond global reset.

Copy lengths and both addresses must be 16-byte aligned. Zero length is a no-op.
Copy supports vector A/C windows, not packing four instruction words per beat.
Descriptors must stay within the allocated vector memory windows. Copy DONE
waits for the final write ACK; a write error sets copy FAULT. Invalid source
reads are reported by the source endpoint's fault status, so check system fault
masks as well as copy status.

## Timing structure

Each router has five ports (local/E/W/S/N) and uses:

1. Two-entry input queues capturing packet and predecoded output route.
2. Per-output round-robin selection with parallel one-hot rank comparisons.
3. Two-entry registered output queues, using registered occupancy for ready.

Route is X before Y and boundary links do not wrap. No combinational ready path
crosses a router; output arbitration space checks cannot depend on the next
router's ready. A packet crosses a router through input and output registers,
trading latency for local timing paths. Separate request/response networks and
reserved endpoint response slots remove the request/response resource cycle.
This is dimension-order mesh routing; simulations are not a formal liveness proof.

Tile integration captures endpoint requests before decode, registers NI packets
and replies, and places two-entry queues after the ALU and after the accumulator.
The original lane multiplication and accumulator feedback datapaths are retained;
Fmax still depends on those paths, memory arbitration, reset fanout and placement.
Core launch PC/pulse and aggregated status are registered per tile. All blocks
use the same clock and synchronous active-low reset. Reset all blocks together;
reset discards in-flight work and completion flags, but does not clear SRAM or
undo committed writes.

## Validation and timing measurement

Run from any directory:

```sh
/path/to/RIGEL/src/tb/system/run.sh
```

The runner lints the synthesis top at full default SRAM depth, then tests:

- BRAM ACK reservations/order/backpressure and physical data visibility.
- NI windows of 1/2/8/16 entries, 64 beat writes per configuration, credit
  exhaustion, ID reuse with duplicate client tags, early decode-error versus
  delayed physical-write completion, memory readback, stalled replies and
  destination-switch fencing. Two sources simultaneously target one endpoint
  with overlapping network IDs to validate response-source isolation.
- Reverse-order network ACKs, original metadata restoration, read fencing and
  reset with queued writes.
- 512 contended packets across all 16 destinations, output stability and
  network reset while packets are in flight.
- Flat-pin host boundary -> 16 vector tiles, masked simultaneous FMA execution,
  actual committed outputs, all-tile remote copies, host/copy arbitration,
  dependent tile execution, repeated partial-mask launch, zero-length copy,
  invalid-write error response and reset recovery. The host then streams 64
  writes with ACK consumer stalls while a tile-0 copy is active, validating
  response ownership and consecutive destination memory write acceptance.

To run selected checks or restrict write-window configurations:

```sh
src/tb/system/run.sh mesh_ni_reorder_tb rigel_mesh_system_tb
WRITE_TEST_DEPTHS="1 8 16" src/tb/system/run.sh mesh_ni_write_window_tb
```

System simulation uses 32 words per bank to keep builds small; full-depth top
elaboration is separately required. Legacy ALU 1/8/16-lane exhaustive tests,
banked memory tests, and write-only NI/DMA tests also passed after the original
memory refactor. The multi-write change is covered by the NI and complete-system
checks above; the legacy write-only bridge remains unchanged.

On a machine with Vivado:

```sh
cd /path/to/RIGEL
vivado -mode batch -source synthesis_mesh.tcl -tclargs 5.0 xc7k480tffg1156-2
```

This requests a 5 ns clock (200 MHz target) and emits post-route timing/utilization
under `reports/mesh`. It is not a measured Fmax. The flow applies explicit host
IO delay budgets (20% of the period) and times synchronous reset; actual board IO
constraints/pins must replace those budgets before deployment. Vivado was not
available in the implementation environment, so physical timing is unmeasured.


## Scheduled AXI system

`rigel_axi_managed_top` is the board integration top: it adds a host descriptor
AXI-Lite slave around `rigel_axi_scheduled_top`, which adds an AXI gateway, a fixed-placement central scheduler,
and an AXI-Lite CDMA controller to the same 4x4 mesh. The original
`rigel_mesh_top` remains the direct ready/valid host boundary.

SmartConnect data masters are XDMA M_AXI and CDMA M_AXI. Data slaves are MIG,
AXI Scratchpad, and this top's 128-bit `s_axi_*` gateway. Connect this top's
32-bit AXI-Lite `m_axi_*` master to the CDMA S_AXI_LITE control port (a separate
control SmartConnect is convenient). The controller exclusively owns that CDMA;
the host must not program its registers concurrently. Use common synchronous
clocks/resets or put AXI clock converters at the external boundaries.

The managed top's `s_task_axi_*` is a separate 32-bit AXI-Lite slave connected
to the host/XDMA control address space. It stages descriptors and consumes
completions. The intermediate scheduled top exposes the same descriptor as a
ready/valid port for alternative hardware producers. A descriptor contains ID, tile, dependency enable/ID, optional copy
source/destination/byte count, copy-only flag, and instruction start PC.
A copy-only task completes after its transfer without launching the core: use
this for DDR-to-Scratchpad staging, then a dependent Scratchpad-to-gateway task. It is sampled on
`task_valid && task_ready`. Rejected descriptors pulse `submit_error` and never
enter a queue. Queue depth defaults to four **waiting** tasks per tile, in
addition to its active task. A stalled producer must keep its descriptor stable.

IDs are 8-bit and cannot be reused before reset. Dependencies must reference an
already accepted ID; this avoids forward references and dependency cycles.
Only the head of each tile FIFO is eligible. A registered round-robin scanner
samples a head, checks dependency and availability in the next stage, reserves
that tile, submits its optional copy, then launches its local PC after copy
completion. Other tiles can execute concurrently while one copy is active.
Only one copy is issued at a time. No automatic tile placement is performed.

The tile remains reserved through completion consumption. The completion port
returns ID, tile and error; `completed`/`failed` are updated when the consumer
accepts it. A failed dependency propagates failure without copying or launching.
The consumer must drain completions for dependent work to progress.
The copy command has a separate state machine: copy stalls do not block the
scanner from launching independent jobs that need no copy or retiring completions. A previous
sticky `done` is not mistaken for a new completion: the scheduler first observes
busy for the new launch. Faults remain sticky in the existing tile core: a job targeted at a faulted
tile fails without copying or launching, and the tile needs reset before reuse. Host direct mask launch is disabled in the
scheduled wrapper to avoid competing launch owners.

Gateway aperture defaults to `0x80000000..0x8fffffff`. `host_tile` selects the tile
for host accesses; the scheduler selects the reserved task tile during its CDMA
copy. The tile selector is sampled independently at AW and AR. The low 28-bit
aperture offset maps directly to tile-local addresses; X/Y are derived from the
linear tile index. The physical AXI aperture is **not** the original 4GB mesh
address space. CDMA source/destination fields contain physical AXI addresses,
not mesh packet addresses. Set `APERTURE_BASE` and `CDMA_BASE` to match Vivado's
address map. Tile instruction/data addresses and PC meanings are unchanged.

The gateway supports one AXI write burst and one read burst independently:
128-bit INCR beats, 16-byte alignment, all byte strobes, up to 256 beats, and no
4KB crossing. Single aligned 32-bit accesses with the corresponding four byte
strobes support instruction (`0x40000`), scheduler (`0x80000`), tile CSR
(`0x100000`) and global control (`0x0ff00000`) windows. Thus existing 4-byte-spaced
programming registers remain accessible. Unsupported address/burst formats are
drained with SLVERR and no mesh request. Unsupported strobes skip that beat and
return SLVERR; earlier valid beats in that burst may already have committed.
Read data has no separate downstream error field in the existing NI protocol;
AXI format errors are reported, while downstream tile read faults use tile fault
status. Write B follows all per-beat physical-commit ACKs, with SLVERR on any
write error. AXI IDs are preserved, and R/B remain stable under backpressure.
Read bursts issue one mesh read at a time; writes exploit the NI outstanding
window and a registered forwarding stage.

The CDMA controller supports simple mode, 32-bit addresses and 16-byte aligned
copies. It resets CDMA for each command, polls reset/idle, writes SA/DA, clears
interrupt status, writes BTT last, then polls idle and completion/error status.
AW and W handshakes are independent. Control-bus errors after BTT also retain
ownership and poll until a valid idle status is observed. DMA errors are reported after idle, when
committed AXI traffic has drained; the next command resets the engine. Default
BTT width is conservatively 23 bits (maximum aligned copy `0x7ffff0` bytes).
The standalone controller can be parameterized to the configured IP BTT width.
No timeout cancels outstanding AXI traffic; unavailable slaves hold the command
pending until external recovery/reset.

Host loading must finish before submitting a job. While scheduled work is
active, host software must not access reserved tile memory, alter its CSR, or
issue gateway data transactions concurrently with a CDMA copy (the aperture
selector is shared). This first integration assumes one active memory owner per
tile, rather than double-buffered overlap inside a tile. Vivado MIG, CDMA,
Scratchpad and SmartConnect IP instances are provided by the board project.

Validation includes scheduler queue/dependency/copy-error/reset tests, CDMA
split AW/W and error-drain tests, and `rigel_axi_scheduled_tb`: actual 4x4 mesh
burst readback, AXI stalls and rejection, narrow instruction/CSR programming,
a behavioral CDMA register model whose copy writes through the real gateway,
host descriptor submission and completion consumption through AXI-Lite, and
two actual FMA jobs with copy-before-launch and cross-tile dependency.
This is not a vendor CDMA/MIG simulation or a physical Fmax measurement.

```sh
src/tb/system/run.sh mesh_task_control_tb mesh_task_scheduler_tb mesh_cdma_controller_tb rigel_axi_scheduled_tb
vivado -mode batch -source synthesis_mesh.tcl -tclargs 5.0 xc7k480tffg1156-2 rigel_axi_managed_top
```

CDMA register behavior follows AMD PG034:
https://docs.amd.com/r/en-US/pg034-axi-cdma/CDMASR-CDMA-Status-Offset-04h
https://docs.amd.com/r/en-US/pg034-axi-cdma/BTT-CDMA-Bytes-to-Transfer-Offset-28h


### Host descriptor CSR window (`s_task_axi_*`)

Map this 256-byte AXI-Lite window separately from the gateway data aperture.
The decoder uses the low 8 address bits. All accesses are aligned 32-bit words,
and writes require all four byte strobes.

| Offset | Register |
|---|---|
| `0x00` | Status: bit 0 pending descriptor, bit 1 sticky submission rejection, bit 2 completion available. Write `2` to clear rejection. |
| `0x04` | Descriptor header: ID [7:0], tile [11:8], dependency enable [12], copy enable [13], copy-only [14]. Other bits zero. |
| `0x08` | Dependency ID [7:0]; other bits zero. |
| `0x0c` | Local instruction PC |
| `0x10` / `0x14` / `0x18` | Copy source / destination / bytes |
| `0x1c` | Write `1` to snapshot and submit the staged descriptor |
| `0x20` | Completion: ID [7:0], tile [11:8], error [12]. Read consumes it only when AXI R is accepted. Empty reads return SLVERR. |
| `0x24` | Tile busy mask [15:0] |
| `0x28` | Tile done mask [15:0], fault mask [31:16] |
| `0x2c` | Host data-aperture tile selector [3:0] |
| `0x40..0x5c` | Successful completion bitmap, eight 32-bit words, low IDs first |
| `0x60..0x7c` | Failed completion bitmap, eight 32-bit words, low IDs first |

Submit with a full staging slot returns SLVERR and preserves the previous
snapshot. Staging registers may be edited for the next task while the previous
snapshot is waiting; this does not change its payload. B success acknowledges
staging, not task execution or descriptor validation: monitor status bit 1 for
scheduler rejection. A completion read stalled on RREADY does not retire the
job or release its dependencies until the read is consumed.

Host sequence: select a tile at `0x2c`, load its data/instructions through the
128-bit gateway (32-bit narrow writes for instruction/CSR words), stage a
header/dependency/PC/copy tuple, then write `1` at `0x1c`. Poll bit 2 of `0x00`
and read `0x20` to consume completions. Track submitted IDs/tiles to avoid host
writes into queued or reserved jobs. The host descriptor AXI-Lite slave can be
used while the independent CDMA control AXI-Lite master is busy.
