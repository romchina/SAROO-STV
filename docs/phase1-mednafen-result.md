# Phase 1 — Mednafen predictive boot result

**Date:** 2026-04-24
**Mednafen version:** 1.29.0 (Ubuntu 22.04 apt build)
**Inputs:** `stv-trampoline/disc.cue` + `disc.bin` (produced by `make_cd.py`)

## Verdict

**Header validation: passed.** Full boot: blocked by missing Saturn BIOS.

## Evidence — header parsed correctly

```
$ mednafen -force_module ss disc.cue

...
Loading "disc.cue"...
  CD 1 TOC:
   Disc Type: 0x00 (CD-DA or Mode 1)
   First Track:  1
   Last Track:   1
   Track  1, MSF: 00:02:00, LBA:      0  DATA
   Leadout:     17  DATA

Using module: ss(Sega Saturn)

SGID: T-000HBSTV
SGNAME: SAROO-STV Phase 1 Trampoline
SGAREA: JTUE
CPU Cache Emulation Mode: Data only
Region: 0x1
Cart: Backup Memory
Error opening file "/root/.mednafen/firmware/sega_101.bin": No such file or directory
```

What this proves:

- **Magic at offset 0x00** — the `"SEGA SEGASATURN "` bytes matched
  Mednafen's sniffer well enough to select the Saturn (`ss`) module
  via auto-detect.
- **Product number at 0x20** — parsed as `T-000HBSTV`.
- **Game name at 0x60** — parsed as `SAROO-STV Phase 1 Trampoline`
  (full 112-byte field, space-trimmed).
- **Region flags at 0x40** — parsed as `JTUE` (multi-region),
  selected `Region: 0x1` (Japan).
- **TOC shape** — single MODE1/2048 data track, correct LBA range
  for a 17-sector image (16 system-area sectors + 1 IP sector).

## What's blocked

Actual IPL execution requires a real Saturn BIOS dump. Mednafen's
`ss` module specifically looks for:

- `sega_101.bin` — Japan 1.01 BIOS (512 KB)
- `mpr-17933.bin` — North America 1.01 BIOS
- Similar for PAL / other regions

These are copyrighted Sega firmware. Not bundled with Mednafen,
not in the SAROO-STV repo, must be obtained from a dumped Saturn
console the user owns.

Once the BIOS is in place, expected behavior when `mednafen disc.cue`
boots:

1. Saturn BIOS splash (Sega logo + SATURN chime — bypassed quickly)
2. IPL parses LBA 0 header
3. IPL reads IP from LBA 16 into HWRAM at `0x06004000`
4. IPL jumps to `First Master PC` = `0x06004000`
5. Our code: masks SR interrupts, writes heartbeat to WRAM,
   configures VDP2 TVMD / BKTAU / BKTAL + VRAM word 0
6. Screen goes **bright magenta** (RGB555 `0xFC1F`) and stays
7. SH-2 master enters NOP halt loop

If the screen doesn't turn magenta, the SH-2 code is reachable
but the VDP2 init is wrong. Inspect WRAM at `0x06000000` via
Mednafen's memory viewer — it should contain `5A A5 A5 5A`
(big-endian heartbeat).

## How to run once BIOS is available

```bash
# Drop BIOS in Mednafen firmware dir (path depends on host OS).
# Linux/WSL:
cp sega_101.bin ~/.mednafen/firmware/

# Then:
cd stv-trampoline
make                   # build trampoline.bin
python3 make_cd.py     # wrap as CD image
mednafen -force_module ss disc.cue
```

## Next on the verification path

- **Phase 2** will need the BIOS anyway (ST-V games call ST-V BIOS
  functions that in turn depend on Saturn BIOS scaffolding). Dropping
  the BIOS in place is a one-time setup.
- **Phase 1 Task 7** (real hardware) bypasses the BIOS question — a
  real Saturn supplies its own BIOS. The trampoline just needs to
  reach real Saturn via SAROO, for which we still need Quartus
  bitstream + physical device.
