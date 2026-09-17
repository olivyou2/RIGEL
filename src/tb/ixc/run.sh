#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/ixc-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
verilator --lint-only --timing -Wno-TIMESCALEMOD --top-module ixc_tb \
    "$ROOT/src/interfaces/rv_if.sv" "$ROOT"/src/ixc/*.sv "$ROOT/src/tb/ixc/ixc_tb.sv"
for config in '2 2 0 4 8 8' '3 3 0 4 8 1' '1 1 0 1 1 8' '3 2 1 3 3 8'; do
    read -r masters slaves zero depth outstanding target_run <<< "$config"
    target="$BUILD/m${masters}s${slaves}z${zero}"
    if ! verilator --binary --timing -Wno-TIMESCALEMOD --top-module ixc_tb \
        -GMASTER_N="$masters" -GSLAVE_N="$slaves" -GZERO_LATENCY="$zero" -GREAD_FIFO_DEPTH="$depth" -GREAD_OUTSTANDING="$outstanding" -GTARGET_RUN="$target_run" \
        --Mdir "$target" "$ROOT/src/interfaces/rv_if.sv" "$ROOT"/src/ixc/*.sv "$ROOT/src/tb/ixc/ixc_tb.sv" > "$BUILD/build.log" 2>&1; then
        cat "$BUILD/build.log"
        exit 1
    fi
    "$target/Vixc_tb"
done

if ! verilator --binary --timing -Wno-TIMESCALEMOD --top-module ixc_bram_tb \
    --Mdir "$BUILD/bram" "$ROOT/src/interfaces/rv_if.sv" "$ROOT"/src/ixc/*.sv "$ROOT/src/bram/bram.sv" \
    "$ROOT/src/bram/bram_stream.sv" "$ROOT/src/tb/ixc/ixc_bram_tb.sv" > "$BUILD/build.log" 2>&1; then
    cat "$BUILD/build.log"
    exit 1
fi
"$BUILD/bram/Vixc_bram_tb"
