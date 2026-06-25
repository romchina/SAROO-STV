# ST-V BIOS HLE — Design Spec

> **Status:** Approved design, pre-implementation.
> **Date:** 2026-06-25
> **Parent:** Yabause ST-V Bridge (`2026-06-25-yabause-stv-bridge-design.md`). This is
> the sub-project that fills the gap the M3/M4 investigation exposed (see the
> CORRECTION section of `docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md`).

## Why this sub-project exists

The M3/M4 bring-up proved that `bakubaku` **hard-depends on the ST-V BIOS**:
- The first-stage boot/loader code at HWRAM `0x06002000` is ST-V BIOS code (found in
  `epr-20091.ic8` at `0x31400` word-swapped), **not** in the cart.
- The game's runtime calls ST-V BIOS services (e.g. a BIOS callback at `0x00005E46`).
- A stock Saturn (Saturn BIOS) has neither. On real SAROO hardware the Saturn mask ROM
  cannot be replaced, so SAROO must provide ST-V functionality by **HLE** — this is
  roadmap Phase 2 ("ST-V BIOS 最小 HLE").

Positive result already in hand: with the corrected game-image load
(`fpr[k] -> HWRAM[k + 0x0600F000]`), Yabause's Saturn SH-2 core **executes real
bakubaku game code**. The only missing piece is the ST-V BIOS environment.

## Goal

Make `bakubaku` run to its attract loop inside the Yabause ST-V bridge (stock Saturn
BIOS) by (1) **reproducing the machine state** that the ST-V BIOS hands to the game,
and (2) **HLE-ing the runtime ST-V BIOS services + peripherals** the game uses.

**Chosen route:** Reproduce handoff state + HLE runtime services (NOT full first-stage
reimplementation, NOT loading the ST-V BIOS into the BIOS slot).

**Success criterion (state/trajectory alignment with MAME — no pixel screenshot):**
after reproduction, the Yabause master SH-2 reaches the attract main loop `0x06036DBC`
and loops stably, with key state (selected VDP2 registers / specific HWRAM words)
matching MAME's frame-1300 reference.

**Non-goals:** reverse-engineering the ST-V BIOS security/loader logic line-by-line;
ST-V BIOS in the emulator BIOS slot; protected games; pixel-accurate rendering/capture
(deferred — verification is state-based); real-hardware SAROO firmware (the twin
informs it but is separate).

## Architecture

```
[offline, MAME]  Capture full machine state at the game-code handoff instant:
                 HWRAM (1MB) + LWRAM (1MB) + master SH-2 registers +
                 VDP1/VDP2 RAM & registers + SCU + SMPC (the minimal set M-HLE-0 fixes).
                     -> export to a state file the bridge can load
[Yabause]        StvBoot loads the state file (writes RAM/VDP, sets SH-2 registers),
                 then runs. The master SH-2 continues the game's OWN code from handoff.
                 (Key insight: the cold-jump fill-loop failed only because R4 was garbage;
                  reproducing the captured registers + RAM makes it terminate correctly.)
[runtime HLE]    As the game runs it calls ST-V BIOS service vectors and reads the
                 315-5649 IOGA / 93C46 EEPROM. Trap the BIOS-service addresses and
                 reimplement the minimal set; add IOGA + EEPROM shims (per M0 data).
[verify]         master SH-2 reaches 0x06036DBC attract loop; compare key state to MAME.
```

- **Reused:** M2 `CART_STV` (kept — the game may read the cart at runtime); the existing
  PC sampler / breakpoint probe (the alignment-verification tooling); MAME as the
  reference oracle throughout.
- **New:** a MAME state-capture script; a state-file loader in the bridge; an IOGA
  memory handler; a 93C46 EEPROM model on SMPC PDR; a BIOS-service trap+HLE layer.

The "snapshot reproduction" is a pragmatic stand-in for the state SAROO's trampoline
would compute on real hardware; it can be refined toward computed reproduction later.

## Components

| Component | Where | Responsibility |
|---|---|---|
| **State capture** | MAME Lua (offline) | At the handoff PC, dump HWRAM/LWRAM/regs/VDP/SCU/SMPC to a file |
| **State loader** | Yabause `StvBoot` (yabause.c) | Read the state file; write RAM/VDP regions; set SH-2 registers; then run |
| **IOGA shim** | memory.c (page 0x004 @ `0x00400000`) | Return M0 IO_MAP idle values (no coin/buttons, region/dipsw); accept Port D writes |
| **EEPROM shim** | smpc.c (PDR1/PDR2 bit-bang) | 93C46 model seeded with `stvbios.nv` contents (per M0 EEPROM) |
| **BIOS-service trap** | sh2 / memory hook | Detect game calls into ST-V BIOS service addresses; reimplement the minimal set |

Each is independently testable: the loader by "RAM matches the file"; IOGA/EEPROM by
read-value assertions; the trap by "service call X produces the MAME-observed effect".

## Inputs

- `bakubaku` cart (already mapped via CART_STV) + `epr-20091.ic8` ST-V BIOS (reference
  only, for tracing/disassembly) + `stvbios.nv` (EEPROM seed) + JP Saturn BIOS (host).
- MAME `stv` `bakubaku` as the live reference oracle.

## Milestones (each independently verifiable)

- **M-HLE-0 — Recon.** In MAME: pin the exact handoff PC (the precise game-code entry).
  Trace, between handoff and attract, every ST-V BIOS service vector the game calls and
  every IOGA/EEPROM access. Determine the **minimal capture set** (which RAM/hardware
  regions the game reads after handoff). **Output:** a capture-set + service/IO list doc.
- **M-HLE-1 — State reproduction.** MAME capture script writes the handoff state file;
  `StvBoot` loads it; verify the master SH-2 runs **past the fill loop** and progresses
  (further than M3's stuck state), tracked by the PC sampler.
- **M-HLE-2 — Runtime shims + service HLE.** Add IOGA + EEPROM shims and the minimal
  BIOS-service HLE; iterate until the master SH-2 reaches `0x06036DBC` and the key state
  matches MAME (success criterion).

## Risks & open questions

1. **Capture-set sufficiency** — if the game reads LWRAM system vars / hardware state we
   did not capture, it diverges. Resolved in M-HLE-0 by tracing the game's reads.
2. **Number of BIOS services** — unknown until traced; a simple puzzle game should use
   few. Handled incrementally in M-HLE-2.
3. **State-file format/size** — ~2 MB RAM + VDP must export/import reliably; pick a
   simple, verifiable binary layout.
4. **Handoff-point precision** — capturing at an inconsistent point yields inconsistent
   state. M-HLE-0 fixes a single deterministic handoff PC.

## Spec → plan

Implementation lives in the Yabause fork (WSL) + a MAME capture script; this repo holds
the spec/plan. After approval, writing-plans produces the M-HLE-0 (+ M-HLE-1) plan; the
later milestones get their own plans once M-HLE-0 fixes the capture set.
