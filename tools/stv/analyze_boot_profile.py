#!/usr/bin/env python3
"""Compare a measured ST-V HWRAM dump with a descriptor boot copy."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from pack_game import IMAGE_SIZE, load_descriptor, sha1


HWRAM_BASE = 0x06000000
HWRAM_SIZE = 0x00100000


def compare_boot_copy(descriptor: dict, image: bytes,
                      hwram: bytes) -> dict[str, int | str | float]:
    profile = descriptor["boot_profile"]
    source = int(profile["source_image_offset"])
    destination = int(profile["destination"], 0) - HWRAM_BASE
    length = int(profile["length"])
    if len(image) != IMAGE_SIZE:
        raise ValueError(f"cart image must be {IMAGE_SIZE:#x} bytes")
    if len(hwram) != HWRAM_SIZE:
        raise ValueError(f"HWRAM dump must be {HWRAM_SIZE:#x} bytes")

    expected = image[source:source + length]
    actual = hwram[destination:destination + length]
    equal = sum(left == right for left, right in zip(expected, actual))
    longest = current = 0
    for left, right in zip(expected, actual):
        if left == right:
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return {
        "game": descriptor["game"],
        "image_sha1": sha1(image),
        "source_image_offset": source,
        "destination": destination + HWRAM_BASE,
        "length": length,
        "equal_bytes": equal,
        "modified_bytes": length - equal,
        "equal_ratio": equal / length,
        "longest_equal_run": longest,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("descriptor", type=Path)
    parser.add_argument("image", type=Path)
    parser.add_argument("hwram", type=Path)
    args = parser.parse_args()
    result = compare_boot_copy(
        load_descriptor(args.descriptor),
        args.image.read_bytes(),
        args.hwram.read_bytes())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
