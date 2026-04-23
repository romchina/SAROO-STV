# stv-trampoline

Minimal Saturn cart-boot stub for SAROO-STV Phase 1.

## What this is

A ~330-byte binary that sits at the CS0 base (`0x02000000`) on the
cartridge A-Bus. Saturn's IPL scans the cart slot on power-up; if it
finds the magic `SEGA SEGASATURN ` at byte 0 followed by a valid
header, it jumps to the First-Master-PC pointer and starts executing
our code.

The trampoline:

1. Masks all SH-2 interrupts (`SR |= 0xF0`).
2. Drops the stack at the top of High Work RAM (`0x06100000`).
3. Writes `0x5AA5A55A` to `0x06000000` (heartbeat — observable in a
   Mednafen save-state dump even without visible VDP2 output).
4. Writes to VDP2 TVMD / BKTAU / BKTAL registers + VRAM word 0 to
   turn the display on with a bright magenta back-screen.
5. Halts in a `nop ; bra halt ; nop` loop.

No slave SH-2 boot, no SCU init, no interrupt vectors set up — just
enough for "we got here and the screen is not black."

## Why pure assembly

Ubuntu's `gcc-sh4-linux-gnu` doesn't support `-m2` (SH-2 target),
and a full SH-ELF GCC toolchain (Yaul / SaturnOrbit) is non-trivial
to install. Since the trampoline is ~25 instructions, hand-assembling
in SH-2 asm is quicker than building a cross-GCC. A richer Phase-2
trampoline (font-based VDP2 text, hex dump, menu) can move to C once
we invest in the full toolchain.

## Build

```bash
make                 # produces trampoline.bin
make test-build      # also prints the disassembly
make clean
```

Requires Ubuntu `binutils-sh-elf` (provides `sh-elf-as`, `sh-elf-ld`,
`sh-elf-objcopy`). Installed via `apt install binutils-sh-elf`.

## Running

### On Saturn via SAROO

Copy `trampoline.bin` to the SD card at
`/SAROO/STV/phase1/trampoline.bin`. When the STM32 firmware's Task-6
`stv_rom_load()` path is wired into the menu (Task 7 bring-up),
selecting this entry will:

- Copy the binary into SDRAM at the 4 MB offset.
- Write FPGA reg 0x30 `ss_rom_base = 4`.
- Write FPGA reg 0x04 `ss_reg_ctrl = 0x0100` (ROM mode).
- Reset the Saturn.

Saturn IPL then boots from the cart and the screen should turn
magenta within a few frames.

### In Mednafen (predictive)

Mednafen boots Saturn from CD images, not raw cart binaries. To
predictively validate the trampoline would run on Mednafen, wrap
`trampoline.bin` into a CUE/BIN CD layout with the Saturn ISO-style
header + ST-V-style security code at LBA 0. This is a deliberate
Phase-2 / Task-7 exercise — Phase 1 stops at "builds and disassembles
as intended".

## Layout

```
0x000  SEGA SEGASATURN  (16 bytes magic)
0x010  SEGA ENTERPRISES (16 bytes maker)
0x020  T-000HBSTVV1.000 (10+6 product + version)
0x030  20260424         (8 bytes date)
0x038  CD-1/1           (8 bytes device info)
0x040  JTUE             (10 bytes region flags)
0x050  J                (16 bytes peripheral compat)
0x060  game name        (112 bytes, space-padded)
0x0D0  reserved         (16 bytes of 0)
0x0E0  _start           (master SH-2 PC, 4 bytes)
0x0E4  _start           (master SH-2 SP seed)
0x0E8  _start           (slave SH-2 PC — unused)
0x0EC  _start           (slave SH-2 SP — unused)
0x0F0  reserved         (16 bytes of 0)
0x100  _start           (entry point — SH-2 code)
0x14C  end
```

## Known limitations (explicit Phase-1 cut)

- Slave SH-2 is not parked cleanly; it runs whatever it boots with.
- No CPU cache init, no SCU init, no VDP1 init.
- VDP2 display mode defaults to NTSC 320x224 without explicit cycle
  patterns; may look different from your TV's expectation.
- Heartbeat word is byte-swapped per Saturn big-endian conventions
  but there's no verification loop (wouldn't reach it anyway).
- No hex dump of ROM contents yet — the original Phase-1 plan
  promised this, moved to Phase-2 / trampoline-v2.
