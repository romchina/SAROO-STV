#!/usr/bin/env python3
"""Build a descriptor-driven 32 MB SAROO-STV cartridge image."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Final


IMAGE_SIZE: Final = 0x02000000
OVERLAY_OFFSET: Final = 0x01F00000
OVERLAY_MAX: Final = 0x1000
HLE_OFFSET: Final = 0x01400000
HLE_MAX: Final = 0x10000
AUXILIARY_OFFSET: Final = 0x01E00000
AUXILIARY_MAX: Final = 0x10000


def sha1(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def load_descriptor(path: Path) -> dict[str, Any]:
    descriptor = json.loads(Path(path).read_text(encoding="utf-8"))
    if descriptor.get("format") != "saroo-stv-game-v1":
        raise ValueError("unexpected game descriptor format")
    if descriptor.get("image_size") != IMAGE_SIZE:
        raise ValueError("descriptor image size must be 32 MB")
    if not descriptor.get("game") or not descriptor.get("roms"):
        raise ValueError("descriptor requires game and ROM entries")
    profile = descriptor.get("boot_profile")
    if profile is not None:
        source = int(profile["source_image_offset"])
        destination = int(profile["destination"], 0)
        length = int(profile["length"])
        entry = int(profile["entry"], 0)
        if source < 0 or length <= 0 or source + length > IMAGE_SIZE:
            raise ValueError("boot profile source range exceeds image")
        if (destination < 0x06000000
                or destination + length > 0x06100000):
            raise ValueError("boot profile destination range exceeds HWRAM")
        if not destination <= entry < destination + length:
            raise ValueError("boot profile entry is outside copied program")
    for entry in descriptor.get("auxiliary", []):
        embed = entry.get("embed")
        if embed is None:
            if entry.get("implemented"):
                raise ValueError(
                    f"{entry['name']}: implemented auxiliary lacks embed metadata")
            continue
        offset = int(embed["image_offset"])
        size = int(entry["size"])
        if (offset < AUXILIARY_OFFSET
                or offset + size > AUXILIARY_OFFSET + AUXILIARY_MAX):
            raise ValueError(
                f"{entry['name']}: auxiliary embed exceeds reserved window")
        expected_saturn = 0x04000000 + offset - 0x01000000
        if int(embed["saturn_address"], 0) != expected_saturn:
            raise ValueError(
                f"{entry['name']}: auxiliary Saturn address does not match CS1")
        destination = int(embed["destination"], 0)
        if destination < 0x06000000 or destination + size > 0x06100000:
            raise ValueError(
                f"{entry['name']}: auxiliary destination exceeds HWRAM")
    return descriptor


def _read_source(directory: Path, entry: dict[str, Any],
                 verify_hashes: bool) -> bytes:
    name = entry["name"]
    data = (directory / name).read_bytes()
    expected_size = int(entry["size"])
    if len(data) != expected_size:
        raise ValueError(
            f"{name}: size {len(data):#x}, expected {expected_size:#x}")
    digest = sha1(data)
    if verify_hashes and digest != entry["sha1"]:
        raise ValueError(f"{name}: SHA-1 {digest}, expected {entry['sha1']}")
    return data


def _word_swap(data: bytes) -> bytes:
    if len(data) & 1:
        raise ValueError("word_swap source has odd size")
    swapped = bytearray(data)
    swapped[0::2], swapped[1::2] = data[1::2], data[0::2]
    return bytes(swapped)


def _apply_operation(image: bytearray, occupied: bytearray, data: bytes,
                     operation: dict[str, Any], source_name: str) -> None:
    kind = operation["type"]
    offset = int(operation["offset"])
    if kind == "copy":
        target = range(offset, offset + len(data))
        payload = data
    elif kind == "word_swap":
        target = range(offset, offset + len(data))
        payload = _word_swap(data)
    elif kind == "load16_byte":
        target = range(offset, offset + len(data) * 2, 2)
        payload = data
    else:
        raise ValueError(f"{source_name}: unsupported load operation {kind}")

    if not target or target[-1] >= len(image):
        raise ValueError(f"{source_name}: load operation exceeds image")
    if any(occupied[index] for index in target):
        raise ValueError(f"{source_name}: load operation overlaps another ROM")
    image[target.start:target.stop:target.step] = payload
    occupied[target.start:target.stop:target.step] = bytes([1]) * len(payload)


def _reserve_module(image: bytearray, occupied: bytearray, offset: int,
                    maximum: int, payload: bytes | None, label: str) -> None:
    if payload is None:
        return
    if len(payload) > maximum:
        raise ValueError(f"{label} exceeds {maximum:#x} bytes")
    if offset < 0 or offset + len(payload) > len(image):
        raise ValueError(f"{label} exceeds image")
    if any(occupied[offset:offset + len(payload)]):
        raise ValueError(f"{label} overlaps game ROM data")
    image[offset:offset + len(payload)] = payload
    occupied[offset:offset + len(payload)] = bytes([1]) * len(payload)


def build_image(descriptor: dict[str, Any], directory: Path,
                verify_hashes: bool = True,
                boot_overlay: bytes | None = None,
                native_hle: bytes | None = None,
                allow_unported_modules: bool = False) -> tuple[bytes, dict]:
    """Return a packed image and deterministic hardware manifest."""
    directory = Path(directory)
    if ((boot_overlay is not None or native_hle is not None)
            and descriptor.get("port_status") != "hardware-candidate"
            and not allow_unported_modules):
        raise ValueError(
            f"{descriptor['game']}: game-specific boot/HLE profile is not ready")

    image = bytearray(IMAGE_SIZE)
    occupied = bytearray(IMAGE_SIZE)
    loaded: dict[str, bytes] = {}
    for entry in descriptor["roms"]:
        data = _read_source(directory, entry, verify_hashes)
        loaded[entry["name"]] = data
        for operation in entry.get("operations", []):
            _apply_operation(image, occupied, data, operation, entry["name"])

    auxiliary: dict[str, dict[str, Any]] = {}
    for entry in descriptor.get("auxiliary", []):
        data = _read_source(directory, entry, verify_hashes)
        embed = entry.get("embed")
        implemented = bool(entry.get("implemented", False))
        if implemented != (embed is not None):
            raise ValueError(
                f"{entry['name']}: implemented flag and embed metadata disagree")
        metadata = {
            "kind": entry["kind"],
            "sha1": sha1(data),
            "implemented": implemented,
            "size": len(data),
        }
        if embed is not None:
            offset = int(embed["image_offset"])
            _reserve_module(image, occupied, offset, len(data), data,
                            f"auxiliary {entry['name']}")
            metadata.update({
                "image_offset": f"0x{offset:08x}",
                "saturn_address": embed["saturn_address"],
                "destination": embed["destination"],
                "persistence": embed.get("persistence"),
            })
        auxiliary[entry["name"]] = metadata

    if boot_overlay is not None and not boot_overlay.startswith(
            b"SEGA SEGASATURN "):
        raise ValueError("boot overlay lacks Saturn hardware ID")
    _reserve_module(image, occupied, OVERLAY_OFFSET, OVERLAY_MAX,
                    boot_overlay, "boot overlay")
    _reserve_module(image, occupied, HLE_OFFSET, HLE_MAX,
                    native_hle, "native HLE")

    canonical_descriptor = json.dumps(
        descriptor, sort_keys=True, separators=(",", ":")).encode("utf-8")
    manifest = {
        "format": "saroo-stv-cart-v2",
        "game": descriptor["game"],
        "title": descriptor.get("title", descriptor["game"]),
        "port_status": descriptor.get("port_status", "unknown"),
        "blockers": list(descriptor.get("blockers", [])),
        "image_size": IMAGE_SIZE,
        "image_sha1": sha1(image),
        "descriptor_sha1": sha1(canonical_descriptor),
        "boot_overlay": {
            "enabled": boot_overlay is not None,
            "image_offset": f"0x{OVERLAY_OFFSET:08x}",
            "max_size": f"0x{OVERLAY_MAX:08x}",
            "sha1": sha1(boot_overlay) if boot_overlay is not None else None,
        },
        "native_hle": {
            "enabled": native_hle is not None,
            "saturn_start": "0x04400000",
            "image_offset": f"0x{HLE_OFFSET:08x}",
            "max_size": f"0x{HLE_MAX:08x}",
            "sha1": sha1(native_hle) if native_hle is not None else None,
        },
        "source_sha1": {name: sha1(data) for name, data in loaded.items()},
        "auxiliary": auxiliary,
        "hardware_windows": [
            {"chip_select": "CS0", "saturn_start": "0x02000000",
             "image_offset": "0x00000000", "size": "0x01000000"},
            {"chip_select": "CS1", "saturn_start": "0x04000000",
             "image_offset": "0x01000000", "size": "0x01000000"},
        ],
        "required_relocation": descriptor.get("required_relocation"),
        "boot_profile": descriptor.get("boot_profile"),
        "resident_profile": descriptor.get("resident_profile"),
        "oracle": descriptor.get("oracle"),
    }
    return bytes(image), manifest


def write_image(output: Path, image: bytes, manifest: dict[str, Any]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    manifest_path = output.with_suffix(output.suffix + ".json")
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {output} ({len(image)} bytes, SHA-1 {manifest['image_sha1']})")
    print(f"wrote {manifest_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("descriptor", type=Path)
    parser.add_argument("rom_directory", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--skip-hash", action="store_true")
    parser.add_argument("--boot-overlay", type=Path)
    parser.add_argument("--native-hle", type=Path)
    parser.add_argument("--allow-unported-modules", action="store_true",
                        help="development only: embed modules for a layout-only game")
    args = parser.parse_args()
    descriptor = load_descriptor(args.descriptor)
    overlay = args.boot_overlay.read_bytes() if args.boot_overlay else None
    hle = args.native_hle.read_bytes() if args.native_hle else None
    image, manifest = build_image(
        descriptor, args.rom_directory, not args.skip_hash, overlay, hle,
        args.allow_unported_modules)
    write_image(args.output, image, manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
