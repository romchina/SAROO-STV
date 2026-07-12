#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YABAUSE_ROOT="${1:-/root/yabause-stv}"
YABAUSE="$YABAUSE_ROOT/build/src/gtk/yabause"
BIOS="$YABAUSE_ROOT/bios/saturn-jp-v100.bin"
LOG="${TMPDIR:-/tmp}/saroo-stv-smpc-smoke.log"

[[ -x "$YABAUSE" ]] || { echo "missing Yabause binary: $YABAUSE" >&2; exit 2; }
[[ -f "$BIOS" ]] || { echo "missing Saturn BIOS: $BIOS" >&2; exit 2; }

make -C "$ROOT/stv-native-hle" test-input-image test-input-pressed-image >/dev/null

run_case() {
    local name="$1" image="$2"
    rm -f "$LOG"
    timeout 5s env DISPLAY="${DISPLAY:-:0}" STV_INVALID=1 STV_SMPCCMD=1 STV_SND=1 \
        "$YABAUSE" -b "$BIOS" --binary="$image:06004000" --nosound \
        >"$LOG" 2>&1 || true
    if grep -Eq 'COMREG=(18|19|1A)' "$LOG" || grep -qi 'invalid opcode' "$LOG"; then
        echo "SMPC $name smoke failed" >&2
        tail -80 "$LOG" >&2
        exit 1
    fi
    if ! grep -q 'COMREG=17' "$LOG"; then
        echo "SMPC $name smoke did not reach the success marker" >&2
        tail -80 "$LOG" >&2
        exit 1
    fi
    if ! grep -q 'COMREG=07' "$LOG" || ! grep -q 'COMREG=06' "$LOG"; then
        echo "SMPC $name smoke did not complete SNDOFF/SNDON" >&2
        tail -80 "$LOG" >&2
        exit 1
    fi
    if ! grep -q 'COMREG=03' "$LOG"; then
        echo "SMPC $name smoke did not park Slave SH-2" >&2
        tail -80 "$LOG" >&2
        exit 1
    fi
    echo "SMPC $name PASS"
}

run_case idle "$ROOT/stv-native-hle/tests/smpc_smoke.bin"
run_case pressed "$ROOT/stv-native-hle/tests/smpc_smoke_pressed.bin"
