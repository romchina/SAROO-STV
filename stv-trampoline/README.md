# stv-trampoline

Minimal Saturn cart-boot stub for SAROO-STV Phase 1.

## What this is

A small binary embedded at cart-image offset 31 MB. FPGA boot overlay
temporarily presents it at CS0 base (`0x02000000`) on the cartridge A-Bus.
Saturn's IPL scans the cart slot on power-up; if it
finds the magic `SEGA SEGASATURN ` at byte 0 followed by a valid
header, it jumps to the First-Master-PC pointer and starts executing
our code.

The trampoline first jumps to its permanent CS1 alias at `0x04F00000` and
closes the boot overlay through `0x2580701C`, restoring the original ST-V
FPR bytes at CS0 offset zero. It then constructs the verified Baku Baku game
image in HWRAM and only afterwards calls the native-HLE installer at
`0x04400088`, so the FPR copy cannot overwrite its relocation veneers. It:

1. Masks all SH-2 interrupts (`SR |= 0xF0`).
2. Drops the stack at the top of High Work RAM (`0x06100000`).
3. Fills `0x0600F000..0x0600FFFF` with the `SEGA` sentinel word.
4. Uses the native CS1 long-copy service at `0x04400000` to copy
   `0xF0000` bytes from FPR `0x02201000` to `0x06010000`; the copy ends
   exactly at the top of HWRAM.
5. Installs the two relocation veneers and verifies the first copied word
   is `0x4F22B0C3` (FPR offset `0x1000`).
6. Writes `0x5AA5A55A` to `0x06000000` (heartbeat — observable in a
   Mednafen save-state dump even without visible VDP2 output).
7. Writes to VDP2 TVMD / BKTAU / BKTAL registers + VRAM word 0 to
   turn the display on with a bright magenta back-screen.
8. Halts in a `nop ; bra halt ; nop` loop.

If the copy verification fails, the heartbeat is `0xDEAD1000` and the
back-screen is red instead of magenta.

No slave SH-2 boot, no SCU init, no interrupt vectors set up yet. This stage
proves the complete cartridge-to-HWRAM game materialization path before the
clean resident and dispatcher begin executing it.

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

Copy `trampoline.bin` to the SD card at `/SAROO/STV/trampoline.bin`.
The `saroo-port-bakubaku` firmware source now exposes a “运行 ST-V 镜像” menu;
after rebuilding and flashing the MCU/Saturn firmware, selecting this entry will:

- Copy the binary into SDRAM at the 4 MB offset.
- Write FPGA reg 0x30 `ss_rom_base = 4`.
- Select raw SDRAM aperture banks through FPGA reg 0x32 while streaming.
- Write FPGA reg 0x04 `ss_reg_ctrl = 0x0100` (ROM mode).
- Reset the Saturn.

Saturn IPL then boots from the cart and the screen should turn
magenta within a few frames.

### In Mednafen (predictive)

```bash
make                 # builds trampoline.bin
python3 make_cd.py   # produces disc.bin + disc.cue
mednafen -force_module ss disc.cue
```

`make_cd.py` takes the cart-flavored `trampoline.bin`, rewrites the
four entry-point words at header offsets 0xE0..0xEC to point at
`0x06004000` (the Saturn IPL's default IP load address), writes the
header to LBA 0, zero-pads through the system area, and drops the
SH-2 code at LBA 16 as the Initial Program. The CUE is MODE1/2048.

Saturn's IPL needs a real Saturn BIOS ROM (`sega_101.bin` for the
Japan v1.01 BIOS) dropped in `~/.mednafen/firmware/` to complete the
boot. Without the BIOS Mednafen aborts at `Error opening file
"/root/.mednafen/firmware/sega_101.bin"` — but not before logging:

```
SGID: T-000HBSTV
SGNAME: SAROO-STV Phase 1 Trampoline
SGAREA: JTUE
Region: 0x1
```

That output alone confirms the header's magic, product number, game
name, and region flags are all in the expected places — i.e. our
cart-boot header is byte-compatible with Saturn's CD-boot header
parser. Full boot verification (seeing magenta on screen) requires
installing a real Saturn BIOS or running on real hardware.

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
0x1CC  end (460 bytes total; still well inside the 4 KB overlay)
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
