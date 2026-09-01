#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
BUILD_DIR="${SCRIPT_DIR}/build"

TOP_MODULE="${1:-fifo_tb}"
if (($# > 0)); then
    shift
fi

for command in iverilog vvp; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "Error: '${command}' is not installed or not in PATH." >&2
        exit 1
    fi
done

SV_FILES=()
while IFS= read -r -d '' file; do
    SV_FILES+=("${file}")
done < <(find "${SRC_DIR}" -type f -name '*.sv' -print0)

if ((${#SV_FILES[@]} == 0)); then
    echo "Error: no SystemVerilog files found under ${SRC_DIR}." >&2
    exit 1
fi

mkdir -p "${BUILD_DIR}"
SIM_FILE="${BUILD_DIR}/${TOP_MODULE}.vvp"

echo "[BUILD] top=${TOP_MODULE}"
iverilog \
    -g2012 \
    -Wall \
    -I "${SRC_DIR}" \
    -s "${TOP_MODULE}" \
    -o "${SIM_FILE}" \
    "${SV_FILES[@]}"

echo "[RUN] ${SIM_FILE}"
vvp "${SIM_FILE}" "$@"
