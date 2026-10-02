# Mesh interconnects

For the complete 4x4 read/write vector system, see `../../../system/README.md`.
`mesh_xy.sv` / `mesh_xy_router.sv` provide registered non-wrapping XY routing;
`mesh_ni.sv` handles read/write requests and responses with a configurable
1..16-entry write window (default 8), allocated write IDs and ordered client ACKs.
Reads and cross-destination transitions fence the write window. The destination
endpoint must support ordered write responses; `vector_tile` provides this.
Each beat retains its own ACK; this is not an AXI burst or block-ACK protocol. The older `mesh.sv` and
write-only NI below remain available for existing integrations.

## Standalone write completion

`mesh_write_ni.sv` adds a write request/response bridge to the existing packet
mesh. It is a write-only NI; read request/response packetization is not yet
implemented. Existing IXC and posted-write DMA interfaces remain unchanged.

## Connections

Instantiate one NI per tile and two `mesh` instances with identical topology:

- NI `mesh_req_tx` -> request mesh `in_ch[tile]`
- request mesh `out_ch[tile]` -> NI `mesh_req_rx`
- NI `mesh_rsp_tx` -> response mesh `in_ch[tile]`
- response mesh `out_ch[tile]` -> NI `mesh_rsp_rx`
- Requester (e.g. `dma_with_write_rsp`) -> NI `write_req` / `write_rsp`
- NI `target_write_req` -> the tile's destination endpoint

Both meshes require `DATA_WIDTH = endpoint DATA_WIDTH + X_BITS + Y_BITS`.
All address/tag/epoch widths must match the NI parameters. Coordinates X/Y
identify this tile and must agree with its mesh array position `x + y*MESH_W`.

The global write address is `{destination_x, destination_y, local_address}`.
The NI strips destination coordinates before presenting the local endpoint
address. Request packet data is `{source_x, source_y, write_data}`. Tag and epoch
are preserved. ACK routes to the source coordinates, retaining local offset,
tag and epoch. The originating NI reconstructs the original global address
on `write_rsp`. Its data is zero (success); error responses are not implemented.
These dedicated write networks have no packet kind field. Sharing networks with
read traffic will require a packet type and corresponding NI demultiplexing.

## Completion and ordering

`write_req.valid && write_req.ready` at the source means the NI captured the
request. It does **not** mean the destination accepted the write.

The destination NI sends an ACK only after
`target_write_req.valid && target_write_req.ready`. This must be the endpoint's
write acceptance/commit boundary. For synchronous BRAM writes, the accepted
edge commits the data. For a command register, ACK means command acceptance,
not completion of the operation launched by that command.

Do **not** connect `target_write_req` to a buffered IXC input and interpret this
ACK as final memory completion: the current IXC handshake only enqueues a write.
A shared target IXC needs end-to-end write response routing before it can sit on
this path. Direct endpoint attachment is supported by this initial bridge.

Each source NI allows one outstanding write, including a stalled completion.
Each destination NI accepts one inbound request until its ACK is injected.
Separate outbound and inbound state permits bidirectional traffic. Requests and
ACKs are registered and held stable during backpressure. The source reserves ACK
storage when accepting a request; master response stalls do not prevent the ACK
from leaving the network. There is no cross-master ordering, read/write ordering,
or multi-endpoint fence guarantee.

`dma_with_write_rsp.sv` reuses the DMA address generators, FIFO and controller,
but counts write **responses** instead of request handshakes. It issues one write
at a time and does not make `ctrl.ready` available for the next descriptor until
all responses are consumed and read issuance is finished. Existing `dma.sv`
retains its posted-write behavior. Replace the DMA instance and connect its new
`write_rsp` port when integrating this path; generated designs are not rewritten
by this change.

Reset is synchronous active-low and discards queued requests and ACKs. Reset the
NIs, networks, DMA and endpoints together. Reset cannot undo writes already
committed to an endpoint.

Request/response separation does not solve routing deadlock within the existing
east/south wraparound mesh. Large cyclic traffic patterns still require a routing
or virtual-channel solution. These tests establish functional write/ACK behavior,
not arbitrary-load deadlock freedom or physical timing.

## Verification

Run `src/tb/mesh_write/run.sh` from any working directory. Strict Verilator builds
with assertions cover two actual 2x1 meshes, simultaneous opposite-direction
writes, destination stalls, ACK consumer stalls, identity/data preservation,
reset with queued writes, delayed DMA ACKs, zero-length descriptors, and an
end-to-end DMA -> mesh -> remote endpoint -> ACK completion path.
