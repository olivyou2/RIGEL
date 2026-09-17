# IXC

Single-beat ready/valid read/write interconnect. `ixc.sv` wires the interfaces
and contains payload registers; `ixc_control.sv` owns valid/busy state,
round-robin selection and response ownership. Reset is synchronous, active low.

## External decode

- `ixc_addr_out[m]` continuously mirrors `read_req[m].addr`. Connect it to an
  external combinational decoder and return its binary index on `ixc_slave_sel[m]`.
- `ixc_write_addr_out[m]` similarly mirrors `write_req[m].addr`; return the write
  decoder index on `ixc_write_slave_sel[m]`. Independent decoders permit concurrent reads/writes.
- Selection and payload are captured together on the master handshake. Hold
  valid, address, data and the corresponding selection stable until ready.
- `SEL_WIDTH` defaults to `max(1, $clog2(SLAVE_N))`. Out-of-range selections
  deassert ready; there is no decode-error response. To encode an invalid value
  for power-of-two slave counts, override `SEL_WIDTH` with an extra bit.
- Master ports are `read_req[MASTER_N]`, `read_rsp[MASTER_N]`, and
  `write_req[MASTER_N]`, all using `rv_if`. Slave ports are the matching
  `slave_read_req`, `slave_read_rsp`, and `slave_write_req` arrays.
  Each channel contains `valid`, `ready`, `addr`, and `data`.
- A write handshake transfers address and data atomically. There is no separate
  write-address channel, write completion response, burst or transaction ID.

## Arbitration, ordering and registers

Each master has a registered read request slot and a two-entry write input FIFO.
Each slave has a two-entry write output FIFO containing address, data and owner. Each slave
arbitrates only requests whose captured selection matches that slave. Read and
write have independent round-robin pointers, advanced when the winning request
enters the slave output register. Counts of one and non-power-of-two counts are
supported; the existing `arbiter` module requires powers of two greater than one,
so this controller implements its own round-robin selection.

Read requests reserve a master response register until the master consumes the
response. Each slave tracks one owner until its response is captured. Thus there
is at most one outstanding read per master and per slave, and no cross-slave
response reordering within a master. A stalled master response does not keep the
slave reserved: other masters can use it after response capture. Slaves must
return exactly one response for each accepted address and hold it until ready.
Address and response handshakes on the same edge are supported.

Writes can queue two requests at each master input and two at each slave output.
A master may issue more writes to the same slave while earlier writes are queued.
Its issued destination remains reserved until all issued writes retire at the
slave handshake. A head request for a different slave waits for that count to
reach zero, preserving master write order across destinations. Independent
slaves can transfer concurrently. There is no ordering guarantee between the
separate read and write channels.

Timing boundaries are master input -> slave request -> master read response.
An uncontended request can enter the slave stage on the edge after master
acceptance; a slave response is registered before being offered to its master.
Both write FIFOs support simultaneous push/pop. Input ready and slave arbitration
space checks use only registered occupancy, with no downstream ready feedback
into the grant or master ready. After pipeline fill, even one master targeting
one continuously ready slave sustains one write per clock. A full FIFO does not
accept a replacement on its first pop edge; the second entry keeps the output
fed while upstream resumes. Destination changes wait for prior writes to retire,
and contention/backpressure can still reduce throughput. Read outstanding limits
are unchanged. Actual Fmax has not been measured.

Reset discards all in-flight transactions. Reset connected endpoints together;
responses from before reset must not be presented after reset.

## Verification

Run from any directory:

```sh
/path/to/RIGEL/src/tb/ixc/run.sh
```

The script runs strict testbench/RTL elaboration lint and self-checking Verilator simulations for
2x2, 3x3, 1x1, and 3x2 with zero-cycle slave responses. Scoreboards check read
routing/data, write routing/data/order, no loss/duplication, stalled output
stability, simultaneous independent slave transfers, invalid decode rejection,
and reset with queued/stalled requests. Random slave readiness, master response
backpressure, and response delays exercise contention and changing destinations.

A directed write test checks 60 consecutive transfer clocks with a single master,
then forces a prolonged stall and drains 200 writes with exact ordering/data
checks. Queue occupancy assertions check for overflow in all configurations.
