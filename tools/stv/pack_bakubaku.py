#!/usr/bin/env python3
"""Compatibility wrapper for the descriptor-driven Baku Baku packer."""

from __future__ import annotations

import argparse
from pathlib import Path

import pack_game


DESCRIPTOR_PATH = Path(__file__).with_name("games") / "bakubaku.json"
DESCRIPTOR = pack_game.load_descriptor(DESCRIPTOR_PATH)
ROMS = tuple(
    (entry["name"], entry["size"], entry["sha1"])
    for entry in DESCRIPTOR["roms"]
)


def build_image(directory: Path, verify_hashes: bool = True,
                boot_overlay: bytes | None = None,
                native_hle: bytes | None = None) -> tuple[bytes, dict]:
    return pack_game.build_image(
        DESCRIPTOR, directory, verify_hashes, boot_overlay, native_hle)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom_directory", type=Path)
    parser.add_argument("output", type=Path, help="32 MB output .bin")
    parser.add_argument("--skip-hash", action="store_true")
    parser.add_argument("--boot-overlay", type=Path)
    parser.add_argument("--native-hle", type=Path)
    args = parser.parse_args()
    overlay = args.boot_overlay.read_bytes() if args.boot_overlay else None
    hle = args.native_hle.read_bytes() if args.native_hle else None
    image, manifest = build_image(
        args.rom_directory, not args.skip_hash, overlay, hle)
    pack_game.write_image(args.output, image, manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
