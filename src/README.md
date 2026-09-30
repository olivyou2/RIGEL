# RTL layout

- `interfaces/`: shared SystemVerilog interfaces
- `common/rv/`: reusable ready/valid transport primitives
- `common/arbitration/`: protocol-independent arbitration primitives
- `blocks/memory/`: BRAM-backed storage blocks and memory adapters
- `blocks/interconnect/`: IXC and mesh interconnect blocks
- `engines/`: compute, DMA, scheduler, SGE, and vector engines
- `generated/`: generated RTL artifacts
- `tb/`: testbenches, grouped by the block they verify
- `top.sv`: top-level integration

Dependencies should point down this list: interfaces are standalone, common
modules depend only on interfaces, blocks may depend on common modules, and
engines/top may depend on all lower layers.
