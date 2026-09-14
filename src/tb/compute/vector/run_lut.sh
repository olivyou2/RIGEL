#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/vector-lut-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
SOURCES=("$ROOT/src/compute/vector/vector_core/vector_exp.sv" "$ROOT/src/compute/vector/vector_core/vector_sqrt.sv")
# Compile the ALU and its LUT dependencies explicitly.
verilator --lint-only --top-module vector_alu \
    "$ROOT/src/compute/vector/vector_core/vector_alu.sv" "${SOURCES[@]}"
for lanes in 1 8 16; do
    if ! verilator --binary --timing -Wno-TIMESCALEMOD --top-module vector_lut_tb \
        -GLANE_SIZE="$lanes" --Mdir "$BUILD/lanes$lanes" \
        "${SOURCES[@]}" "$ROOT/src/compute/vector/vector_core/vector_alu.sv" \
        "$ROOT/src/tb/compute/vector/vector_lut_tb.sv" > "$BUILD/build.log" 2>&1; then
        cat "$BUILD/build.log"
        exit 1
    fi
    "$BUILD/lanes$lanes/Vvector_lut_tb"
done
