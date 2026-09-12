#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/ixc-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
verilator --lint-only --top-module ixc "$ROOT"/src/ixc/*.sv
for config in '2 2 0' '3 3 0' '1 1 0' '3 2 1'; do
    read -r masters slaves zero <<< "$config"
    target="$BUILD/m${masters}s${slaves}z${zero}"
    if ! verilator --binary --timing -Wno-TIMESCALEMOD --top-module ixc_tb \
        -GMASTER_N="$masters" -GSLAVE_N="$slaves" -GZERO_LATENCY="$zero" \
        --Mdir "$target" "$ROOT"/src/ixc/*.sv "$ROOT/src/tb/ixc/ixc_tb.sv" > "$BUILD/build.log" 2>&1; then
        cat "$BUILD/build.log"
        exit 1
    fi
    "$target/Vixc_tb"
done
