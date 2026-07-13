#!/usr/bin/env python3
"""Verify the cold-boot trampoline's fixed layout and handoff ordering."""

from __future__ import annotations

import struct
import subprocess
import sys
from pathlib import Path


def symbols(path: Path) -> dict[str, int]:
    output = subprocess.check_output(
        ["sh-elf-nm", "-n", str(path)], text=True
    )
    result: dict[str, int] = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) == 3:
            result[fields[2]] = int(fields[0], 16)
    return result


def main() -> int:
    elf = Path(sys.argv[1])
    binary = Path(sys.argv[2])
    profile = sys.argv[3] if len(sys.argv) > 3 else "bakubaku"
    data = binary.read_bytes()
    sym = symbols(elf)

    assert data.startswith(b"SEGA SEGASATURN ")
    assert len(data) <= 0x1000, "trampoline exceeds the FPGA boot overlay"
    assert sym["_start"] == 0x02000100
    assert sym["alias_entry"] < 0x02001000
    assert (sym["fill_sega_page"] < sym["call_long_copy"] < sym["call_install"]
            < sym["call_resident_init"]
            < sym["verify_game_copy"]
            < sym["show_status"])

    common_longs = (
        0x0600F000, 0x53454741, 0x00000400,
        0x04400000, 0x04400088,
        0x04400800, 0x06000000, 0xFFFFFE00,
        0x04401200,
        0x04401400,
        0x5AA5A55A, 0xDEAD1000,
    )
    if profile == "shienryu":
        profile_longs = (
            0x06003000, 0x02200000, 0x0003E400, 0x53454741,
        )
        summary = "Shienryu 0xF9000-byte measured program copy"
    elif profile == "shienryu-run":
        profile_longs = (
            0x06003000, 0x02200000, 0x0003E400, 0x53454741,
            0x04401700,
        )
        summary = "Shienryu clean-resident game entry"
    else:
        profile_longs = (
            0x06010000, 0x02201000, 0x0003C000, 0x4F22B0C3,
        )
        summary = "Baku 0xF0000-byte shifted FPR copy"
    required_longs = common_longs + profile_longs
    for value in required_longs:
        assert struct.pack(">I", value) in data, f"missing literal {value:#010x}"

    print(
        f"verified cold boot: {summary}, diagnostics"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
