# ST-V BIOS HLE — M-HLE-0/1 Recon + Result

**Date:** 2026-06-25. Reference oracle: MAME 0.242 `stv bakubaku -bios jp1`.

## HANDOFF (capture point)

Tooling note: MAME's `-debug` debugger runs headless under WSL and `save <file>,addr,len`
works, but `printf` output goes to the debugger console (not stdout), so instruction-
precise register capture via the debugger is not capturable. Lua `io`/`cpu.state`/
`mem:read_u32` **are** capturable and fast (1 MB dumped in <0.1 s). So capture is done
in Lua at a **fixed deterministic frame**.

- **Capture point:** frame **1185**, master SH-2 **PC = 0x060335E4** (game running its
  own code, just past the fill loop; M0 noted this region does coin-lockout setup).
- **Deterministic:** yes (MAME is deterministic for fixed BIOS + no input).
- **Registers (frame 1185):** R4=45A07060, R5=00004058, R7=45A07058, R15=060FFFDC,
  PC=060335E4, PR=0603358C, GBR=060D28C8, VBR=06000000, rest mostly 0. (Full set in
  `stvstate/regs.txt`.)

## CAPTURE_SET (what the reproduction must include)

| Region | Captured in M-HLE-1? | Notes |
|---|---|---|
| HWRAM `0x06000000`–`0x060FFFFF` (1 MB) | ✅ | includes vectors + game image |
| LWRAM `0x00200000`–`0x002FFFFF` (1 MB) | ✅ | |
| master SH-2 registers | ✅ | regs.txt |
| **Sound RAM `0x25A00000`–`0x25A7FFFF` (512 KB)** | ❌ **MISSING** | **must add** — see RUNTIME below |
| 68000 sound CPU state / VDP / SCU / SMPC hardware regs | ❌ | TBD as divergences surface |

## RUNTIME — first blocker found (M-HLE-2 entry)

After reproduction, the master SH-2 executes the game's own code, then **stalls in a
3-instruction poll loop at `0x060335DC`-`0x060335E4`**:
```
R2 = [0x06033664]        ; pointer = 0x25A07DBC (Sound RAM)
R2 = word @[R2]          ; read 16-bit value from sound RAM
R3 = word @[0x06033662]  ; expected = 0x4F4B  ("OK")
if R2 != R3: loop        ; wait until sound RAM[0x25A07DBC] == 0x4F4B
```
This is the **68000 sound-driver "OK" handshake**: the main SH-2 waits for the sound CPU
to write `0x4F4B` to sound RAM `0x25A07DBC`. Our capture omitted sound RAM and the 68000,
so the value never appears → infinite wait.

**M-HLE-2 first task options:** (a) capture+reproduce sound RAM and run the 68000 sound
driver (faithful), or (b) HLE the handshake (write `0x4F4B` to `0x25A07DBC`, pretend the
sound CPU is ready) to get past it and surface the next dependency. Likely (b) first to
map the remaining blockers quickly, then decide on real sound handling.

## M-HLE-1 RESULT (positive)

- State capture from MAME (regs + HWRAM + LWRAM) works and is byte-correct
  (`HWRAM[0x0604B440]=62637604`, matches MAME).
- `StvBoot` reproduces it; **the master SH-2 executes bakubaku's own game code from the
  reproduced state without crashing.** This strongly validates the core thesis: Yabause's
  Saturn SH-2 core runs ST-V game code given the right machine state.
- The remaining work (M-HLE-2) is providing the runtime environment the game polls/calls:
  starting with the sound handshake above, then IOGA/EEPROM/VDP/interrupts, until the
  master SH-2 reaches the attract main loop `0x06036DBC` matching MAME.

## Reproduce
```
# capture (MAME): /tmp/capstate.lua dumps regs+HWRAM+LWRAM at frame 1185 to stvstate/
mame bakubaku -bios jp1 -video none -autoboot_script /tmp/capstate.lua -seconds_to_run 45
# run (Yabause): StvBoot loads stvstate/, SH2Int=1, VideoCore=2, --stvboot
STV_SELFTEST=1 STV_PCSAMPLE=1 STV_PCTRACE=1 build/src/gtk/yabause -b bios/saturn-jp-v100.bin --stvboot
```

## M-HLE-2 progress (sound handshake cleared; attract loop reached)

- The frame-1185 capture froze the game *in* the 68000 sound-handshake wait (it polls
  sound RAM `0x25A07DBC` for `0x4F4B`; at frame 1185 the 68000 hadn't written it yet).
- Probe across frames: `0x4F4B` appears at sound RAM `0x05A07DBC` by **frame 1220**, when
  PC is already the attract loop `0x06036DBC`. So **capture at frame 1300** (stable attract)
  instead — the handshake is done and the game is past the sound wait.
- Added sound RAM (`0x05A00000`, 512 KB) to the capture + StvBoot load.
- **RESULT:** the master SH-2 reaches and runs bakubaku's **attract main loop**
  (`0x06036DBA`-`0x06036DCA`), matching MAME's attract PC region → state/trajectory
  success criterion met at the PC level.
- **OPEN (next M-HLE-2):** the loop spins un-throttled (~1e9 instr/15s, not 60 fps), so
  it is NOT vblank-synced — the attract likely isn't advancing/rendering in real time.
  Next: VDP2 vblank + SCU interrupt delivery so the main loop frame-syncs like MAME.
- Minor: sound-RAM readback after load showed a discrepancy (`snd05` hi word != 0x4F4B);
  not on the attract path (capture-at-attract skips the sound check), noted for later.

## M-HLE-2 frame-sync — SOLVED (vblank via VDP2/SCU register reproduction)

- Decoded the attract main loop: it spin-waits while a flag byte at `0x060833F0` is > 0,
  incrementing a counter at `0x06083400`. The flag is cleared by the **vblank IRQ handler**.
- Root cause of the un-throttled spin: we reproduced RAM + SH-2 regs but NOT the VDP2/SCU
  hardware registers, so the SCU interrupt mask (SpeedySetup default) blocked vblank → the
  flag never cleared → infinite spin.
- Fix: capture VDP2 regs (`0x05F80000`, 0x120B; TVMD=0x8000 = display on) + SCU regs
  (`0x05FE0000`, 0x100B; IMS=0xFFFFE1FC = vblank-IN unmasked) at frame 1300, and write them
  in StvBoot via `MappedMemoryWrite{Word,Long}Nocache` (capture: `/tmp/capstate2.lua`).
- RESULT: spin (1.4e9 instr/15s) → frame-paced (~100 loop hits/s, bounded). The SH-2 now
  idles at `0x0600205A` between vblanks and runs the attract loop once per frame = vblank
  delivery works, the frame-wait flag is being cleared.
- OPEN: confirm the attract animation actually ADVANCES (per-frame work / VDP output) vs
  just frame-pacing an idle — needs a finer PC trace or VDP VRAM/output check. Plus the
  capture set is now HWRAM+LWRAM+sndram+VDP2regs+SCUregs (SMPC/VDP1 still not captured).

## CORRECTION (same session): "frame-sync SOLVED" was WRONG — it's an interrupt crash

Fine-grained PC sampling (every 0x1000 instr) + a user-observed crash overturned the
previous "frame-sync solved" claim:
- The SH-2 spends ~99.8% of time at `0x0600205A`, which decodes to `BF 0x0600205A`
  (branch-to-self infinite loop) — it is the **general illegal-instruction exception
  handler** (vec[4] @0x06000010 = 0x06002056 -> ... -> 0x0600205A trap loop). So the
  reduced instruction count was the SH-2 **trapped after an illegal instruction**, NOT
  clean frame-paced idle.
- A separate run crashed with "Master SH2 invalid opcode" at PC=0x0070FE00 (jumped via a
  garbage R3) — same class of failure (execution corrupted into garbage).
- Root cause (revised): reproducing VDP2/SCU regs DID make vblank fire (real progress),
  but the game cannot HANDLE the interrupt — the interrupt environment is not fully
  reproduced (missing SMPC/VDP1 state and/or the handler's expected setup), so taking the
  IRQ lands in an inconsistent context -> illegal instruction (trap loop) or garbage jump.
- HONEST STATUS: vblank now triggers, but interrupt handling crashes. This is the real
  M-HLE-2 hard part (not done). Lesson: verify advancement, don't infer success from a
  spin stopping — a stopped spin can be a crash into a trap loop.

## M-HLE-2 vblank crash — TRACED to game handler 0x06035278 (incomplete capture set)

Instrumented SH2HandleInterrupts (STV_IRQ env). The interrupt DISPATCH is fully correct:
- vblank fires: `[IRQ#0] vec=0x40 lvl=15 handler=0x06001F48` (vector 0x40 = VBLANK-IN, correct).
- 0x06001F48 = standard BIOS dispatch stub (6-byte entries: push R0; BRA common; MOV #vec,R0).
- common handler 0x06001FFC: `SHLL2 R0` (0x40<<2=0x100), then loads the user handler from a
  table: `R6 = [0x06000900 + 0x100] = [0x06000A00] = 0x06035278` (valid game code), `JSR @R6`.
- So it correctly calls the GAME's vblank handler at **0x06035278**.
- The crash is INSIDE 0x06035278: it reads hardware state we did NOT reproduce (SMPC input /
  VDP1 / etc.), computes a bad value, and either hits an illegal instruction (-> trap loop at
  0x0600205A `BF` self) or jumps to garbage (observed PC=0x0070FE00 via a bad R3).

ROOT CAUSE (verified): the capture set is still incomplete. Reproduced so far: HWRAM, LWRAM,
sound RAM, VDP2 regs, SCU regs. The vblank handler 0x06035278 needs MORE: almost certainly
**SMPC** (it runs each frame and reads pads via SMPC) and likely **VDP1** regs/VRAM, possibly
VDP2 VRAM/CRAM. NEXT: either trace 0x06035278's out-of-captured-range reads, or comprehensively
capture SMPC + VDP1 (regs+VRAM) + VDP2 VRAM/CRAM at frame 1300 and reproduce them, then re-test.
