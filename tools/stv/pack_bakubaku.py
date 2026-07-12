#!/usr/bin/env python3
"""Build a deterministic SAROO-STV image from a Baku Baku ROM directory."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Final


IMAGE_SIZE: Final = 0x02000000
CS_WINDOW_SIZE: Final = 0x01000000

ROMS: Final = (
    ("fpr17969.13", 0x100000, "1d226db72d6ef68fd294f60659df7f882b25def6"),
    ("mpr17970.2", 0x400000, "dcc241dcabea59325decfba3fd5e113c07958422"),
    ("mpr17971.3", 0x400000, "99587eea528a6413cacc3e4d3d1dbfff57b03dca"),
    ("mpr17972.4", 0x400000, "e86acd8096f2aee5f5e3ddfd3abb4f5c2b11df66"),
    ("mpr17973.5", 0x400000, "eeb5efb5216ab8b8fdee4656774bbd5a2a5b2d42"),
)


def _read_rom(directory: Path, name: str, size: int, sha1: str,
              verify_hashes: bool) -> bytes:
    path = directory / name
    data = path.read_bytes()
    if len(data) != size:
        raise ValueError(f"{name}: size {len(data):#x}, expected {size:#x}")
    digest = hashlib.sha1(data).hexdigest()
    if verify_hashes and digest != sha1:
        raise ValueError(f"{name}: SHA-1 {digest}, expected {sha1}")
    return data


def _word_swap(data: bytes) -> bytes:
    swapped = bytearray(data)
    swapped[0::2], swapped[1::2] = data[1::2], data[0::2]
    return bytes(swapped)


def build_image(directory: Path, verify_hashes: bool = True,
                boot_overlay: bytes | None = None) -> tuple[bytes, dict]:
    """Return the canonical 32 MB cart image and deterministic manifest."""
    directory = Path(directory)
    loaded = {
        name: _read_rom(directory, name, size, sha1, verify_hashes)
        for name, size, sha1 in ROMS
    }

    image = bytearray(IMAGE_SIZE)
    fpr = loaded["fpr17969.13"]
    image[0x0000001:0x0200001:2] = fpr
    image[0x0200000:0x0300000] = fpr
    image[0x0300000:0x0400000] = fpr

    for index, name in enumerate(("mpr17970.2", "mpr17971.3",
                                  "mpr17972.4", "mpr17973.5")):
        offset = 0x0400000 + index * 0x0400000
        image[offset:offset + 0x0400000] = _word_swap(loaded[name])

    if boot_overlay is not None:
        if len(boot_overlay) > 0x1000:
            raise ValueError("boot overlay exceeds 4 KB")
        if not boot_overlay.startswith(b"SEGA SEGASATURN "):
            raise ValueError("boot overlay lacks Saturn hardware ID")
        image[0x01F00000:0x01F00000 + len(boot_overlay)] = boot_overlay

    manifest = {
        "format": "saroo-stv-cart-v1",
        "game": "bakubaku",
        "image_size": IMAGE_SIZE,
        "image_sha1": hashlib.sha1(image).hexdigest(),
        "boot_overlay": {
            "enabled": boot_overlay is not None,
            "image_offset": "0x01f00000",
            "max_size": "0x00001000",
            "sha1": (hashlib.sha1(boot_overlay).hexdigest()
                     if boot_overlay is not None else None),
        },
        "source_sha1": {
            name: hashlib.sha1(loaded[name]).hexdigest()
            for name, _, _ in ROMS
        },
        "hardware_windows": [
            {
                "chip_select": "CS0",
                "saturn_start": "0x02000000",
                "image_offset": "0x00000000",
                "size": "0x01000000",
            },
            {
                "chip_select": "CS1",
                "saturn_start": "0x04000000",
                "image_offset": "0x01000000",
                "size": "0x01000000",
            },
        ],
        "required_relocation": {
            "original": "0x03000000-0x03ffffff",
            "replacement": "0x04000000-0x04ffffff",
            "reason": "SAROO PCB does not route Saturn AA24 to the FPGA",
        },
    }
    return bytes(image), manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom_directory", type=Path)
    parser.add_argument("output", type=Path, help="32 MB output .bin")
    parser.add_argument("--skip-hash", action="store_true",
                        help="development only: accept noncanonical ROM hashes")
    parser.add_argument("--boot-overlay", type=Path,
                        help="Saturn-header trampoline, at most 4 KB")
    args = parser.parse_args()

    overlay = args.boot_overlay.read_bytes() if args.boot_overlay else None
    image, manifest = build_image(args.rom_directory, not args.skip_hash, overlay)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    manifest_path = args.output.with_suffix(args.output.suffix + ".json")
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8")
    print(f"wrote {args.output} ({len(image)} bytes, SHA-1 {manifest['image_sha1']})")
    print(f"wrote {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
