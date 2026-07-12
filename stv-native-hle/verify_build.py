#!/usr/bin/env python3
"""Static build checks for the SH-2 relocation veneer image."""

from pathlib import Path
import re
import subprocess
import sys


def tool_output(*args: str) -> str:
    return subprocess.check_output(args, text=True)


def main() -> int:
    elf = Path(sys.argv[1] if len(sys.argv) > 1 else "stv-native-hle.elf")
    symbols = tool_output("sh-elf-nm", "-n", str(elf))
    disasm = tool_output("sh-elf-objdump", "-d", str(elf))

    expected = {
        "stv_long_copy_reloc": 0x04400000,
        "stv_memmove_reloc": 0x04400034,
        "stv_install_reloc_veneers": 0x04400088,
    }
    required = {}
    for name, expected_address in expected.items():
        match = re.search(rf"^([0-9a-fA-F]+)\s+\w\s+{name}$", symbols,
                          re.MULTILINE)
        if not match:
            raise SystemExit(f"missing symbol: {name}")
        address = int(match.group(1), 16)
        if not 0x04400000 <= address < 0x04410000:
            raise SystemExit(f"{name} outside CS1 HLE window: {address:#x}")
        if address != expected_address:
            raise SystemExit(
                f"{name} moved: {address:#x}, trampoline expects {expected_address:#x}")
        required[name] = address

    for instruction in ("cmp/hs", "mov.l", "jmp", "dt"):
        if instruction not in disasm:
            raise SystemExit(f"expected instruction absent: {instruction}")

    raw = elf.with_suffix(".bin").read_bytes()
    for value in (0x03000000, 0x03400000, 0x01000000,
                  0x0604AFD4, 0x06053C98, 0xD001402B, 0x00090009,
                  required["stv_long_copy_reloc"],
                  required["stv_memmove_reloc"]):
        if value.to_bytes(4, "big") not in raw:
            raise SystemExit(f"required big-endian word absent: {value:#010x}")

    print("verified", len(raw), "bytes", required)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
