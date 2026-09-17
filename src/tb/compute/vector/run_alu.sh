#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/vector-alu-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
SOURCES=("$ROOT/src/interfaces/rv_if.sv" "$ROOT/src/compute/vector/vector_core/vector_alu.sv" "$ROOT/src/compute/vector/vector_core/vector_exp.sv" "$ROOT/src/compute/vector/vector_core/vector_sqrt.sv")
verilator --lint-only --timing -Wno-TIMESCALEMOD --top-module vector_alu_tb \
    "${SOURCES[@]}" "$ROOT/src/tb/compute/vector/vector_alu_tb.sv"
for lanes in ${ALU_TEST_LANES:-1 8 16}; do
    if ! verilator --binary --timing -Wno-TIMESCALEMOD --top-module vector_alu_tb \
        -GLANE_SIZE="$lanes" --Mdir "$BUILD/lanes$lanes" "${SOURCES[@]}" \
        "$ROOT/src/tb/compute/vector/vector_alu_tb.sv" > "$BUILD/build.log" 2>&1; then
        cat "$BUILD/build.log"
        exit 1
    fi
    "$BUILD/lanes$lanes/Vvector_alu_tb"
done
