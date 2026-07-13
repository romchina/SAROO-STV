#!/usr/bin/env python3
"""Verify a packed SAROO-STV image, manifest, and embedded boot modules."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


IMAGE_SIZE = 0x02000000
OVERLAY_OFFSET = 0x01F00000
HLE_OFFSET = 0x01400000


def sha1(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def verify(image_path: Path, manifest_path: Path, overlay_path: Path,
           hle_path: Path) -> dict:
    image = image_path.read_bytes()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    overlay = overlay_path.read_bytes()
    hle = hle_path.read_bytes()

    if len(image) != IMAGE_SIZE:
        raise ValueError(f"image size {len(image):#x}, expected {IMAGE_SIZE:#x}")
    if manifest.get("format") not in {"saroo-stv-cart-v1", "saroo-stv-cart-v2"}:
        raise ValueError("unexpected manifest format")
    if manifest.get("image_size") != IMAGE_SIZE:
        raise ValueError("manifest image size mismatch")
    if manifest.get("image_sha1") != sha1(image):
        raise ValueError("manifest image SHA-1 mismatch")
    if not overlay.startswith(b"SEGA SEGASATURN "):
        raise ValueError("boot overlay lacks Saturn hardware ID")
    if image[OVERLAY_OFFSET:OVERLAY_OFFSET + len(overlay)] != overlay:
        raise ValueError("boot overlay bytes mismatch")
    if image[HLE_OFFSET:HLE_OFFSET + len(hle)] != hle:
        raise ValueError("native HLE bytes mismatch")

    overlay_meta = manifest.get("boot_overlay", {})
    hle_meta = manifest.get("native_hle", {})
    if not overlay_meta.get("enabled") or overlay_meta.get("sha1") != sha1(overlay):
        raise ValueError("boot overlay manifest mismatch")
    if not hle_meta.get("enabled") or hle_meta.get("sha1") != sha1(hle):
        raise ValueError("native HLE manifest mismatch")

    for name, metadata in manifest.get("auxiliary", {}).items():
        if not metadata.get("implemented"):
            continue
        offset = int(metadata["image_offset"], 0)
        size = int(metadata["size"])
        payload = image[offset:offset + size]
        if len(payload) != size or sha1(payload) != metadata.get("sha1"):
            raise ValueError(f"embedded auxiliary mismatch: {name}")

    windows = manifest.get("hardware_windows")
    expected_windows = [
        {
            "chip_select": "CS0", "saturn_start": "0x02000000",
            "image_offset": "0x00000000", "size": "0x01000000",
        },
        {
            "chip_select": "CS1", "saturn_start": "0x04000000",
            "image_offset": "0x01000000", "size": "0x01000000",
        },
    ]
    if windows != expected_windows:
        raise ValueError("hardware window manifest mismatch")

    return {
        "image_sha1": sha1(image),
        "overlay_sha1": sha1(overlay),
        "native_hle_sha1": sha1(hle),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--boot-overlay", required=True, type=Path)
    parser.add_argument("--native-hle", required=True, type=Path)
    args = parser.parse_args()
    manifest = args.manifest or args.image.with_suffix(args.image.suffix + ".json")
    result = verify(args.image, manifest, args.boot_overlay, args.native_hle)
    print(f"verified {args.image} ({IMAGE_SIZE:#x} bytes, SHA-1 {result['image_sha1']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
