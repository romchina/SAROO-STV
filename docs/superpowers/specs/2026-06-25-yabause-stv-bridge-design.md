# Yabause ST-V Bridge — Design Spec

> **Status:** Approved design, pre-implementation.
> **Date:** 2026-06-25
> **Relationship:** Software twin / development testbed for SAROO-STV. De-risks
> roadmap Phase 2–3 logic in software before real-hardware bring-up
> (`docs/STV-ROADMAP.md`). Reuses the Phase 1 trampoline
> (`docs/superpowers/plans/2026-04-24-stv-phase1-rom-boot.md`).

## Goal

Run a real ST-V arcade ROM (**Baku Baku Animal**, `bakubaku`) inside a modified
**vanilla Yabause (SDL port)** emulating a **stock Sega Saturn with a real Saturn
BIOS** — i.e. the exact configuration SAROO targets on real hardware. A new C
module plays the role of SAROO's FPGA + STM32 firmware: it maps the ST-V ROM into
the Saturn A-Bus cartridge space, overlays a Saturn-bootable header so the Saturn
BIOS boots into our stub, performs minimal ST-V initialization, jumps into the
game, and shims the ST-V peripherals (315-5649 I/O, 93C46 EEPROM) the game touches.

**Definition of success:** `bakubaku` reaches attract mode / paints its first real
frame, booted by the **Saturn BIOS** on Yabause's Saturn core, via the bridge
(milestone **M4**). Playable input is a follow-on (M5).

**Explicit non-goals:** running the real ST-V BIOS in the BIOS slot (that is "MAME
stv on Yabause", a different approach we rejected); protected ST-V games (`bakubaku`
is unprotected); cycle-accurate A-Bus timing (Yabause models an idealized bus —
timing/electrical fidelity is a real-hardware-only concern, out of scope here); FPGA
or STM32 verification (hardware-only, out of scope).

## Why this configuration

A stock Saturn (Saturn BIOS only) **cannot** boot an ST-V cart unaided:

- The ST-V ROM header magic is `SEGA ST-V(TITAN)` (confirmed by dumping
  `fpr17969.13:0x00`), **not** the Saturn `SEGA SEGASATURN ` the Saturn IPL looks
  for. The Saturn BIOS therefore drops to its CD/multiplayer screen and never
  touches the cart code.
- The game expects the **ST-V BIOS** to have initialized the machine and to provide
  ST-V BIOS services, plus the **315-5649** I/O chip and a **93C46** EEPROM.

Bridging those gaps in software is exactly SAROO roadmap Phase 2–3. Doing it here,
in an environment with full memory/breakpoint/trace visibility and MAME `stv.cpp`
as a known-good reference, de-risks the firmware before any hardware bring-up.

`bakubaku` is region **J** (header `0x40 = 'J'`), matching the supplied JP Saturn
BIOS (v1.00, 1994) and the JP ST-V BIOS — region-consistent end to end.

## Architecture

```
Saturn BIOS power-on
  └─► scans A-Bus cart → reads our OVERLAID Saturn boot header
      (magic SEGASATURN, entry → stub)
        └─► jumps into stub  = [reused Phase 1 trampoline] + minimal ST-V init
              └─► jumps to bakubaku's real entry in the A-Bus-mapped ROM
                    └─► game runs on VDP1 / VDP2 / SCSP (Yabause native Saturn)
                          └─► game reads 315-5649 I/O / 93C46 EEPROM
                                → serviced by our shims
```

- **Reused:** Phase 1 trampoline (already verified bootable under Yabause); Yabause's
  native Saturn core (SH-2 / VDP1 / VDP2 / SCSP / SMPC).
- **New:** cart mapping, header overlay, ST-V init, I/O shim, EEPROM shim, input
  translation — all in one module.

### Base emulator

Vanilla **Yabause SDL port**, built and run in **WSL2 Ubuntu** with WSLg for
display. Chosen for the smallest, most hackable bus/cart code. Fallback if Yabause's
accuracy or build bitrot blocks the real ST-V boot flow: **Kronos** (maintained,
more accurate Yabause fork).

## Components

All new logic lives in one focused module, `yabause/src/stv_bridge.c` (+ header),
registered as a new cartridge type `STV_BRIDGE` and hooked into the A-Bus
read/write path.

| Component | SAROO analog | Responsibility |
|---|---|---|
| **Cart mapper** | FPGA CS0/CS1/CS2 mapping | Load `bakubaku`'s 5 IC files into the A-Bus cart space (`0x02000000`+) per MAME `stv.cpp` address map |
| **Header overlay** | FPGA dynamic header patch | On reads of the first N header bytes, return a Saturn boot header (SEGASATURN magic + boot struct, entry → stub) without altering game code at other addresses |
| **ST-V init stub** | trampoline + BIOS HLE | Set A-Bus wait/SCU config; perform the minimal ST-V init the game assumes; jump to the game entry |
| **I/O shim (315-5649)** | FPGA I/O emulation | Intercept I/O-region reads/writes; return idle/no-coin + region/dipsw defaults |
| **EEPROM shim (93C46)** | FPGA EEPROM emulation | Serve `stvbios.nv` default contents so BIOS/game find valid settings |
| **Input** | SMPC→JAMMA translation | Map keyboard keys to JAMMA coin / Start / directions (M5 only) |

Each component has one purpose and a narrow interface to the bus layer, so it can be
understood and tested in isolation.

## Inputs (assets in hand)

- ST-V BIOS set `stvbios.zip` (JP variants among 9) — used as **reference** for the
  init/handoff behavior to replicate, **not** loaded into the BIOS slot.
- Game `bakubaku.zip` — `fpr17969.13` (1 MB) + `mpr17970.2`…`mpr17973.5` (4 MB each).
- Saturn BIOS — JP v1.00 (1994), 512 KB — loaded into Yabause's BIOS slot.
- `stvbios.nv` (93C46 default image) — seed for the EEPROM shim.

## Milestones (incremental, each independently verifiable)

- **M0 — Recon (no emulator changes).** From MAME `stv.cpp`: `bakubaku` IC→address
  map, the ST-V boot/init sequence, the 315-5649 register map, EEPROM wiring. Dump
  `bakubaku`'s real entry point / ST-V exec-header layout. **Output:** a concrete
  "bridge spec" (memory map + minimal init + I/O/EEPROM behavior). *Highest priority
  — several downstream unknowns resolve here.*
- **M1 — Baseline.** Build vanilla Yabause (SDL) in WSL2; boot a known Saturn game
  with the JP Saturn BIOS; confirm baseline + WSLg display.
- **M2 — Mapping.** Add `STV_BRIDGE`; map `bakubaku` into the A-Bus; confirm bytes
  present via Yabause memory read.
- **M3 — Boot bridge.** Header overlay + stub: Saturn BIOS boots into the stub, which
  jumps to `bakubaku`'s entry; confirm execution arrival via breakpoint/trace.
- **M4 — Shims.** Add I/O + EEPROM shims; iterate until **`bakubaku` reaches attract
  mode / first frame** ← *success criterion*.
- **M5 — Playable.** Add input translation; insert coin and play.

## Risks & open questions

1. **`bakubaku` real entry + ST-V exec-header layout unknown** (`0xF0` region is all
   zero; ST-V layout differs from Saturn IP). Resolved in **M0**.
2. **Vanilla Yabause build bitrot / accuracy gaps on Ubuntu 22.04** may surface in
   the real ST-V boot flow → escalate to **Kronos**.
3. **Which ST-V BIOS services `bakubaku` calls early** is uncertain; trace and shim
   incrementally in M4. A simple puzzle game should call few.
4. **Yabause's debugger is weaker than MAME's** → run the same game in MAME `stv` as
   a known-good reference for cross-checking state.

## Spec → implementation

Implementation modifies a **Yabause fork** (separate clone); this SAROO-STV repo
holds the spec and plan. After spec approval, the next step is the writing-plans
skill to produce a task-by-task implementation plan (starting with M0 recon).
