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
    data = binary.read_bytes()
    sym = symbols(elf)

    assert data.startswith(b"SEGA SEGASATURN ")
    assert len(data) <= 0x1000, "trampoline exceeds the FPGA boot overlay"
    assert sym["_start"] == 0x02000100
    assert sym["alias_entry"] < 0x02001000
    assert (sym["fill_sega_page"] < sym["call_long_copy"]
            < sym["call_install"] < sym["verify_game_copy"]
            < sym["show_status"])

    required_longs = (
        0x0600F000, 0x53454741, 0x00000400,
        0x06010000, 0x02201000, 0x0003C000,
        0x4F22B0C3, 0x04400000, 0x04400088,
        0x5AA5A55A, 0xDEAD1000,
    )
    for value in required_longs:
        assert struct.pack(">I", value) in data, f"missing literal {value:#010x}"

    print(
        "verified cold boot: SEGA page, 0xF0000-byte copy, "
        "post-copy veneers, diagnostics"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
