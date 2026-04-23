#!/usr/bin/env bash
# FPGA simulation runner. Invoke from host or WSL — iverilog only.
# Usage: bash run_sim.sh [testbench_name]
#   e.g.  bash run_sim.sh tb_cs0_rom     (default)

set -euo pipefail

TB="${1:-tb_cs0_rom}"

cd "$(dirname "$0")"

# SSMaster.v source files (real RTL, unchanged from upstream)
DUT_SRC=(
    ../SSMaster.v
    ../cachebus.v
    ../cacheblk.v
    ../memhub.v
    ../tsdram.v
)

# Megafunction + SDRAM stubs
STUB_SRC=(
    stubs/mainpll_stub.v
    stubs/cdcfifo_stub.v
    stubs/sdram_tie_off.v
)

# Output VVP file
VVP="${TB}.vvp"

echo "=== compile ==="
iverilog -g2012 -Wall -Wno-timescale \
    -D SIM=1 \
    -o "${VVP}" \
    "${TB}.v" \
    "${STUB_SRC[@]}" \
    "${DUT_SRC[@]}"

echo "=== run ==="
vvp "${VVP}"

echo "=== done ==="
echo "VCD: $(pwd)/${TB}.vcd"
echo "Open with: gtkwave ${TB}.vcd"
