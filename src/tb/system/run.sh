#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/rigel-system.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
sources=()
while IFS= read -r source; do sources+=("$ROOT/$source"); done < "$ROOT/src/system/files.f"
# Strict full-size (512 words/bank) synthesis-top elaboration.
verilator --lint-only --timing -Wno-TIMESCALEMOD --top-module rigel_mesh_top "${sources[@]}"

verilator --lint-only --timing -Wno-TIMESCALEMOD --top-module rigel_axi_managed_top "${sources[@]}"

tops=("$@")
if [[ ${#tops[@]} -eq 0 ]]; then tops=(banked_bram_with_rsp_tb mesh_xy_tb mesh_ni_reorder_tb mesh_ni_write_window_tb mesh_task_control_tb mesh_task_scheduler_tb mesh_cdma_controller_tb rigel_axi_scheduled_tb rigel_mesh_system_tb); fi
for top in "${tops[@]}"; do
 variants=(default)
 if [[ "$top" == mesh_ni_write_window_tb ]]; then
     read -r -a variants <<< "${WRITE_TEST_DEPTHS:-1 2 8 16}"
 fi
 for variant in "${variants[@]}"; do
     parameters=()
     if [[ "$variant" != default ]]; then parameters=(-GWRITE_DEPTH="$variant"); fi
     target="$BUILD/${top}_${variant}"
     if ! verilator --binary --assert --timing -Wno-TIMESCALEMOD -j 4 \
         --output-split 20000 --output-split-cfuncs 200 --top-module "$top" \
         ${parameters[@]+"${parameters[@]}"} --Mdir "$target" "${sources[@]}" "$ROOT/src/tb/system/$top.sv" > "$BUILD/build.log" 2>&1; then
         cat "$BUILD/build.log"
         exit 1
     fi
     "$target/V$top"
 done
done
