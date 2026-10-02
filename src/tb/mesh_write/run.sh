#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/mesh-write-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
for top in mesh_write_ni_tb dma_with_write_rsp_tb dma_mesh_write_tb; do
    if ! verilator --binary --assert --timing -Wno-TIMESCALEMOD --top-module "$top" \
        --Mdir "$BUILD/$top" "$ROOT/src/interfaces/rv_if.sv" "$ROOT/src/interfaces/dma_ctrl_if.sv" \
        "$ROOT/src/common/rv/fifo.sv" "$ROOT/src/common/rv/skid.sv" "$ROOT/src/common/arbitration/arbiter.sv" \
        "$ROOT/src/common/arbitration/arbiter_skid.sv" "$ROOT"/src/blocks/interconnect/mesh/*.sv \
        "$ROOT/src/engines/dma/dma_control.sv" "$ROOT/src/engines/dma/dma_src_addr.sv" \
        "$ROOT/src/engines/dma/dma_dst_addr.sv" "$ROOT/src/engines/dma/dma_with_write_rsp.sv" \
        "$ROOT/src/tb/mesh_write/$top.sv" > "$BUILD/build.log" 2>&1; then
        cat "$BUILD/build.log"
        exit 1
    fi
    "$BUILD/$top/V$top"
done
