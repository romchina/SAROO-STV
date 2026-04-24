# Phase 1 — Emulator end-to-end verification

**Date:** 2026-04-24
**Host:** Windows 11 + WSL2 Ubuntu 22.04
**Emulators used:** Mednafen 1.29.0, Yabause 0.9.14
**Inputs:** `stv-trampoline/disc.cue` (+ `disc.bin`), `stv-trampoline/trampoline.bin`

## Verdict

**End-to-end verified under Yabause.** The SH-2 code assembled in
`trampoline.s` runs on an emulated Saturn, reaches the VDP2 init
sequence, and paints the back screen bright magenta (RGB555 `0xFC1F`).

Mednafen CD-boot path is blocked by Saturn's lead-in security ring
(not a bug in this project) — see findings below.

## Path that works

```
cd stv-trampoline
make                       # trampoline.bin (cart-layout)
python3 make_cd.py         # disc.bin/cue for header validation;
                           # also extractable to pure IP (see below)

# Pure SH-2 boot via Yabause --binary, bypassing CD + BIOS security:
dd if=disc.bin of=/tmp/ip.bin bs=2048 skip=16
yabause -a -b ~/.yabause/bios.bin --binary=/tmp/ip.bin:0x06004000
```

Within a few seconds the Yabause window fills with magenta. The
trampoline then halts the master SH-2 in a `nop/bra halt` loop.

Convenience wrapper: `stv-trampoline/run_yabause.sh` launches Yabause
for a 60-second observation window.

## Mednafen predictive: header OK, autoboot blocked by security ring

The following was exercised against Mednafen with a real BIOS
(`sega_101.bin`, Japan 1.01) staged in `~/.mednafen/firmware/`:

```
$ mednafen -force_module ss disc.cue

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
  Region: 0x1
```

CD header parsing is good. But the emulated Saturn BIOS refuses to
autoboot and drops into the CD player UI (what users call the
"nine-ball screen"). Root cause: the Saturn boot ROM checks the disc
lead-in subchannel Q for a proprietary Sega security signature
pressed only on authentic discs. Burned/homebrew images don't carry
it, and Mednafen honors this check because it runs the real BIOS
unmodified. `ss.cd_sanity 0` and `ss.bios_sanity 0` were tried — no
effect, since the gate is inside BIOS code, not in Mednafen's sanity
layer.

The real SAROO-STV target is **cart boot via CS0/CS1/CS2**, which
never touches the CD path, so this isn't a blocker for the project.
Mednafen CD predictive is limited to "header parses correctly" as
a sanity signal.

## Bugs this verification exposed

### 1. `make_cd.py` wrote cart-style entry points into CD-header fields

CD-boot header fields at `0xE0..0xFF` have a different layout from
the cart header the same bytes live under when the binary runs from
CS0. The old `make_cd.py` wrote `0x06004000` into all of `0xE0 /
0xE4 / 0xE8 / 0xEC` (cart-style "master PC / SP / slave PC / SP"),
which a Saturn IPL re-interprets as:

- `0xE0`: IP size in sectors → `0x06004000` sectors (nonsense)
- `0xE8`: 1st Read Addr → usable
- `0xEC`: 1st Read Size in bytes → `0x06004000` bytes (also nonsense)

That produced the "disc format cannot be read" screen before autoboot
even began.

Fixed layout (per libyaul / common Saturn homebrew):

| Offset | Field              | Value          |
|--------|--------------------|----------------|
| 0xE0   | IP size (sectors)  | `0x00000001`   |
| 0xE4   | reserved           | `0`            |
| 0xE8   | 1st Read Address   | `0x06004000`   |
| 0xEC   | 1st Read Size (B)  | `0x00000800`   |
| 0xF0   | reserved           | `0`            |
| 0xF4   | reserved           | `0`            |
| 0xF8   | 1st Master PC      | `0x06004000`   |
| 0xFC   | 1st Slave  PC      | `0x06004000`   |

### 2. VDP2 BKTAU/BKTAL addresses were wrong

The trampoline used `0x25F80020 / 0x25F80022` for BKTAU/BKTAL. Those
addresses are actually **BGON** and **MZCTL**. Real VDP2 back screen
table registers are:

- BKTAU: `0x25F800AC`
- BKTAL: `0x25F800AE`

With the wrong addresses, the trampoline wrote `0` to BGON (harmless,
disables layers anyway) and `0` to MZCTL (harmless), while BKTAU/BKTAL
were never written and pointed nowhere useful.

### 3. BKCLMD polarity

Comment in the original said `BKCLMD=1 → single-color`. Empirically
the opposite: with `BKTAU=0x8000` (bit 15 set) only scanline 0 showed
magenta and the rest stayed black — i.e. bit 15 selects **per-line**
color, not single-color. Setting `BKTAU=0` fills the whole screen.
Comment and value updated accordingly.

## Mednafen path — how to run for header-only sanity

Still useful as a parse-stage check. Requires a user-owned Saturn
BIOS (`sega_101.bin` or equivalent region dump) in
`~/.mednafen/firmware/`:

```bash
cd stv-trampoline
make
python3 make_cd.py
mednafen -force_module ss disc.cue
```

Expected: header fields parse (SGID / SGNAME / SGAREA), then
autoboot stalls in CD player UI as documented.

## Next on the verification path

- **Phase 1 Task 7 (real hardware)** — SAROO cart boot bypasses
  the Saturn CD security ring entirely. This is the real Phase 1
  exit condition. Needs: Quartus bitstream build + flash, STM32
  firmware build + flash, SD card with a ST-V ROM dump.
- **Phase 2** begins once real hardware shows the trampoline painting
  a screen and dumping 256 bytes of ST-V ROM.
