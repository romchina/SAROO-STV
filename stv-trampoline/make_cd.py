#!/usr/bin/env python3
"""
Builds a minimal Saturn CD image from the trampoline binary for
Mednafen predictive testing.

The cart-boot trampoline runs from CS0 (0x02000000). Saturn's CD IPL
boots differently: it parses the LBA 0 header, loads an Initial
Program (IP) from LBA 16 onward into HWRAM at 0x06004000, then jumps
to the "First Master PC" field in the header.

To exercise CD boot we need:
  - LBA 0..15: system area. Byte 0 = "SEGA SEGASATURN ". We put our
    header (with First Master PC = 0x06004000) at LBA 0 and zero-pad
    the rest of the system area.
  - LBA 16..: the IP itself — same SH-2 machine code as cart trampoline.
    Requires the code be linked at 0x06004000 (position-dependent mov.l
    literal-pool displacement).

This script reads the already-built cart trampoline.bin to lift the
header + the raw SH-2 instruction bytes, rewrites the First-Master-PC
fields to 0x06004000, then writes disc.bin + disc.cue.

NOTE: The SH-2 code in our stub is PC-relative (mov.l @(disp,pc)) for
all data accesses, so relocating it to 0x06004000 doesn't require a
rebuild. If that stops being true (e.g., once we add abs-addressed
jumps / tables), this script must gain a proper re-link step.
"""

import pathlib
import struct
import sys

SECTOR_BYTES     = 2048       # MODE1/2048
SYSTEM_AREA_LBA  = 16         # IP begins at LBA 16
CART_BIN         = pathlib.Path(__file__).parent / "trampoline.bin"
OUT_BIN          = pathlib.Path(__file__).parent / "disc.bin"
OUT_CUE          = pathlib.Path(__file__).parent / "disc.cue"

IP_LOAD_ADDR     = 0x06004000  # Saturn IPL's default IP load target

def main() -> int:
    if not CART_BIN.exists():
        print(f"ERROR: {CART_BIN} not found. Run `make` first.", file=sys.stderr)
        return 1

    data = CART_BIN.read_bytes()
    if len(data) < 0x100:
        print(f"ERROR: {CART_BIN} is shorter than header (256 B)", file=sys.stderr)
        return 1

    header = bytearray(data[:0x100])
    code   = data[0x100:]

    # Header fields 0xE0..0xEF hold four 32-bit words:
    #   0xE0: master-SH2 initial PC / IP size placeholder
    #   0xE4: master-SH2 initial SP seed
    #   0xE8: slave-SH2 initial PC
    #   0xEC: slave-SH2 initial SP
    # For CD boot we want all "program entry" fields to point at the
    # HWRAM IP load target so whichever one the IPL uses, we land on
    # our code.
    for off in (0xE0, 0xE4, 0xE8, 0xEC):
        struct.pack_into(">I", header, off, IP_LOAD_ADDR)

    # Assemble the disc image.
    #   LBA 0        : 2 KB header (ours is 256 B, pad with zeros)
    #   LBA 1..15    : 15 zero sectors (system area padding)
    #   LBA 16..     : IP sectors containing the SH-2 code
    disc = bytearray(SECTOR_BYTES * SYSTEM_AREA_LBA)   # LBA 0..15
    disc[0:len(header)] = header

    # Pad IP to whole sectors
    ip_pad = (-len(code)) % SECTOR_BYTES
    ip_blob = code + b"\x00" * ip_pad
    disc.extend(ip_blob)

    # Enforce minimum CD image — Mednafen accepts tiny but not empty
    if len(disc) < SECTOR_BYTES * (SYSTEM_AREA_LBA + 1):
        disc.extend(b"\x00" * (SECTOR_BYTES * (SYSTEM_AREA_LBA + 1) - len(disc)))

    OUT_BIN.write_bytes(disc)

    cue = (
        'FILE "disc.bin" BINARY\n'
        '  TRACK 01 MODE1/2048\n'
        '    INDEX 01 00:00:00\n'
    )
    OUT_CUE.write_text(cue)

    print(f"disc.bin: {len(disc)} bytes ({len(disc)//SECTOR_BYTES} sectors)")
    print(f"IP size : {len(ip_blob)} bytes ({len(ip_blob)//SECTOR_BYTES} sectors)")
    print(f"disc.cue written")
    return 0

if __name__ == "__main__":
    sys.exit(main())
