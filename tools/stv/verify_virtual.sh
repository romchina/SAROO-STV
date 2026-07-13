#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROM_DIR=""
OUTPUT_DIR="$ROOT/out/stv"
CI_MODE=0

usage() {
    cat <<'EOF'
Usage: bash tools/stv/verify_virtual.sh [--ci] [--rom-dir DIR] [--output-dir DIR]

Runs every hardware-independent SAROO-STV check.  With --rom-dir, also builds
and verifies the diagnostic and game-entry 32 MB Baku Baku images.

--ci skips the Saturn menu C build because Ubuntu does not package an SH-2
GCC; all binutils-only SH-2 images and other open-source checks still run.
EOF
}

while (($#)); do
    case "$1" in
        "") shift ;;
        --ci) CI_MODE=1; shift ;;
        --rom-dir) ROM_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

cd "$ROOT"

required_tools=(python3 make gcc iverilog vvp sh-elf-as sh-elf-ld \
    sh-elf-objcopy sh-elf-objdump sh-elf-nm)
if [[ "$CI_MODE" -eq 0 ]]; then
    required_tools+=(sh-elf-gcc)
fi
for tool in "${required_tools[@]}"; do
    command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 2; }
done

step() { printf '\n==== %s ====\n' "$1"; }

step "packer unit tests"
python3 -m unittest discover -s tools/stv/tests -v

step "vendor project source membership"
python3 tools/stv/verify_vendor_projects.py

if [[ "$CI_MODE" -eq 0 ]]; then
    step "Saturn menu firmware clean build"
    make -C Firm_Saturn clean all
    test "$(wc -c < Firm_Saturn/ramimage.bin)" -eq 393216
else
    step "Saturn menu firmware skipped (Ubuntu has no packaged SH-2 GCC)"
fi

step "MCU streaming-loader host tests"
make -C Firm_MCU/tests clean test

step "FPGA FMC/CS0/CS1/overlay simulation"
bash FPGA/sim/run_sim.sh tb_cs0_rom

step "native SH-2 HLE clean build and layout verification"
make -C stv-native-hle clean stv-native-hle.bin
python3 stv-native-hle/verify_build.py stv-native-hle/stv-native-hle.elf

step "diagnostic and game-entry trampoline verification"
make -C stv-trampoline clean trampoline.bin trampoline-run.bin
python3 stv-trampoline/verify_build.py \
    stv-trampoline/trampoline.elf stv-trampoline/trampoline.bin
python3 stv-trampoline/verify_build.py \
    stv-trampoline/trampoline-run.elf stv-trampoline/trampoline-run.bin
python3 - <<'PY'
from pathlib import Path
run = Path("stv-trampoline/trampoline-run.bin").read_bytes()
assert bytes.fromhex("04400a00") in run, "run trampoline lacks native handoff"
print("verified game-entry handoff 0x04400A00")
PY

if [[ -x /root/yabause-stv/build/src/gtk/yabause ]]; then
    step "native SMPC asynchronous INTBACK smoke"
    bash tools/stv/run_smpc_smoke.sh /root/yabause-stv
else
    step "native SMPC smoke skipped (Yabause twin not installed)"
fi

if [[ -n "$ROM_DIR" ]]; then
    step "canonical 32 MB image build and verification"
    mkdir -p "$OUTPUT_DIR"
    python3 tools/stv/pack_bakubaku.py "$ROM_DIR" \
        "$OUTPUT_DIR/bakubaku-saroo.bin" \
        --boot-overlay stv-trampoline/trampoline.bin \
        --native-hle stv-native-hle/stv-native-hle.bin
    python3 tools/stv/pack_bakubaku.py "$ROM_DIR" \
        "$OUTPUT_DIR/bakubaku-saroo-run.bin" \
        --boot-overlay stv-trampoline/trampoline-run.bin \
        --native-hle stv-native-hle/stv-native-hle.bin
    python3 tools/stv/verify_saroo_image.py \
        "$OUTPUT_DIR/bakubaku-saroo.bin" \
        --boot-overlay stv-trampoline/trampoline.bin \
        --native-hle stv-native-hle/stv-native-hle.bin
    python3 tools/stv/verify_saroo_image.py \
        "$OUTPUT_DIR/bakubaku-saroo-run.bin" \
        --boot-overlay stv-trampoline/trampoline-run.bin \
        --native-hle stv-native-hle/stv-native-hle.bin
else
    step "canonical image build skipped (pass --rom-dir to enable)"
fi

printf '\nVIRTUAL ACCEPTANCE PASS\n'
