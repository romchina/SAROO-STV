#!/usr/bin/env python3
"""Emit GNU assembler definitions from an ST-V game boot profile."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def assembler_flags(descriptor: dict) -> list[str]:
    profile = descriptor["boot_profile"]
    length = int(profile["length"])
    if length <= 0 or length % 4:
        raise ValueError("boot copy length must be a positive multiple of four")
    values = {
        "GAME_DST": int(profile["destination"], 0),
        "GAME_SRC": int(profile["source_saturn_address"], 0),
        "GAME_LONG_COUNT": length // 4,
        "GAME_FIRST_WORD": int(profile["first_word"], 0),
    }
    result: list[str] = []
    for name, value in values.items():
        result.extend(("--defsym", f"{name}=0x{value:08X}"))
    return result


def main() -> int:
    descriptor = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    print(" ".join(assembler_flags(descriptor)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
