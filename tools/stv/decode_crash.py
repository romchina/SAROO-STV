#!/usr/bin/env python3
"""Decode the clean resident SH-2 crash record from an HWRAM dump."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


HWRAM_BASE = 0x06000000
CRASH_ADDRESS = 0x06000B80
MAGIC = 0xDEADE001
RAW_WORDS = 22
RAW_FIELDS = (
    "VBR", "GBR", "MACL", "MACH", "PR",
    "R14", "R13", "R12", "R11", "R10", "R9", "R8", "R7",
    "R6", "R5", "R4", "R3", "R2", "R1", "R0", "PC", "SR",
)


def decode(data: bytes, base_address: int = HWRAM_BASE) -> dict[str, int]:
    offset = CRASH_ADDRESS - base_address
    size = (2 + RAW_WORDS) * 4
    if offset < 0 or offset + size > len(data):
        raise ValueError("dump does not contain the crash-record address")
    words = struct.unpack_from(f">{2 + RAW_WORDS}I", data, offset)
    if words[0] != MAGIC:
        raise ValueError(f"crash magic {words[0]:#010x}, expected {MAGIC:#010x}")
    if words[1] != RAW_WORDS:
        raise ValueError(f"crash record has {words[1]} words, expected {RAW_WORDS}")
    return dict(zip(RAW_FIELDS, words[2:]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dump", type=Path, help="binary memory dump containing 0x06000B80")
    parser.add_argument("--base-address", type=lambda value: int(value, 0),
                        default=HWRAM_BASE,
                        help="address corresponding to dump byte zero (default: 0x06000000)")
    args = parser.parse_args()
    fields = decode(args.dump.read_bytes(), args.base_address)
    for name in ("PC", "PR", "SR", "VBR", "GBR", "MACH", "MACL"):
        print(f"{name:4} = {fields[name]:08X}")
    for index in range(15):
        name = f"R{index}"
        print(f"{name:4} = {fields[name]:08X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
