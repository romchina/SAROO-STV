# Yabause ST-V Bridge — M3 Boot Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) tracking. (Note: Agent dispatch was unavailable during M2; inline execution via executing-plans is the fallback.)

**Goal:** Get the master SH-2 to start executing the bakubaku ST-V IP. A new `StvBoot()` routine HLE-initializes the Saturn machine (reusing `YabauseSpeedySetup`), copies the ST-V IP from CS0 into HWRAM exactly as the ST-V BIOS does (per M0), and seeds the master SH-2 PC to the M0-measured entry `0x060249FE`. Verification: an SH-2 code breakpoint at `0x060249FE` fires (we start there) and execution proceeds within HWRAM (`0x06xxxxxx`).

**Architecture:** Yabause already has a "seed the SH-2 and run" path (`MappedMemoryLoadExec`, used by `--binary`): `YabauseResetNoLoad()` → `YabauseSpeedySetup()` → set `MSH2->regs.PC`. `StvBoot()` mirrors this but, instead of loading a file, copies CS0's plain IP mirror (`0x02200000`, 1 MB) into HWRAM (`0x06000000`) and jumps to `0x060249FE`. A `--stvboot` CLI arg in the GTK port triggers it after `yui_window_run`, exactly как `--binary` does. This is the software stand-in for SAROO's trampoline; it models "the Saturn BIOS has initialized the machine, then the cart takes over."

**Tech Stack:** C (Yabause core: yabause.c, sh2core.c breakpoints, memory.c); GTK port main.c CLI; built in WSL2; software renderer (`VideoCore=2`).

## Global Constraints

- Yabause fork: `/root/yabause-stv/yabause/src/` (WSL git repo). Build: `cd /root/yabause-stv/build && make -j$(nproc)`; binary `build/src/gtk/yabause`.
- Run Linux cmds via `wsl.exe bash -lc "…"`. Software renderer only (`VideoCore=2`).
- Requires M2 complete: `CART_STV` maps bakubaku into CS0; `0x02200000` (plain IP mirror) returns the fpr17969.13 bytes (verified: `0x02200000` = "SEGA ST-V(TITAN)").
- M0-measured values (verbatim, from `docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md`):
  - IP source in CS0: plain mirror at A-Bus `0x02200000`, 1 MB (`fpr17969.13`).
  - IP destination: HWRAM `0x06000000`.
  - Master SH-2 entry PC: `0x060249FE`; SP (R15) at entry: `0x060FFFE8`.
  - Main loop (attract) PC: `~0x06036DBC`; game-code entry: `0x0604B446`.
  - Slave SH-2: held in RESET until the game releases it via SMPC — leave default reset state.
- Config: real Saturn BIOS loaded (`BiosPath` set, `emulatebios=0`) so `YabauseSpeedySetup` copies the real BIOS vector/function tables.
- Scope: get execution INTO the IP and confirm it runs. Running correctly to attract (which needs the IOGA/EEPROM shims the IP touches) is M4 — NOT required here.

---

## Task 1: StvBoot() + `--stvboot` trigger

**Files:**
- Modify: `/root/yabause-stv/yabause/src/yabause.c` (add `StvBoot`)
- Modify: `/root/yabause-stv/yabause/src/yabause.h` (declare `StvBoot`)
- Modify: `/root/yabause-stv/yabause/src/gtk/main.c` (add `--stvboot` arg)

**Interfaces:**
- Consumes: `YabauseResetNoLoad()`, `YabauseSpeedySetup()`, `MappedMemoryReadLongNocache`/`MappedMemoryWriteLongNocache`, `MSH2`, `SH2GetRegisters`/`SH2SetRegisters` (all in yabause.c scope).
- Produces: `void StvBoot(void);` — declared in yabause.h, callable from gtk/main.c.

- [ ] **Step 1: Declare StvBoot in yabause.h**

Near the other `Yabause*` prototypes, add:
```c
void StvBoot(void);
```

- [ ] **Step 2: Implement StvBoot in yabause.c**

Add (place it right after `MappedMemoryLoadExec`):
```c
//////////////////////////////////////////////////////////////////////////////
// STV bridge boot: HLE-init the Saturn, copy the ST-V IP from CS0 to HWRAM,
// and seed the master SH-2 to the ST-V IP entry (see M0 recon spec).
//////////////////////////////////////////////////////////////////////////////
void StvBoot(void)
{
   u32 i;

   YabauseResetNoLoad();
   YabauseSpeedySetup();   // HLE machine init using the loaded Saturn BIOS tables

   // Copy ST-V IP: CS0 plain mirror 0x02200000 (1 MB) -> HWRAM 0x06000000.
   // (This overwrites the SpeedySetup HWRAM tables at 0x06000000; the ST-V IP
   //  brings its own, exactly as the ST-V BIOS does on real hardware.)
   for (i = 0; i < 0x100000; i += 4)
      MappedMemoryWriteLongNocache(MSH2, 0x06000000 + i,
         MappedMemoryReadLongNocache(MSH2, 0x02200000 + i));

   // Seed master SH-2 to the M0-measured IP entry.
   SH2GetRegisters(MSH2, &MSH2->regs);
   MSH2->regs.PC  = 0x060249FE;
   MSH2->regs.R[15] = 0x060FFFE8;
   SH2SetRegisters(MSH2, &MSH2->regs);

   // Slave SH-2 left in reset (default) until game releases it via SMPC.
}
```

- [ ] **Step 3: Add the --stvboot trigger in gtk/main.c**

In the CLI arg loop (after the `--binary=` branch, mirroring its structure), add:
```c
	 // STV bridge boot
	 else if (strcmp(argv[i], "--stvboot") == 0) {
	    yui_window_run(YUI_WINDOW(yui));
	    StvBoot();
	    autostart = 1;
	 }
```
(`yabause.h` is already included in main.c. Setting `autostart=1` is harmless — the window is already running; it avoids a second run call.)

- [ ] **Step 4: Build**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv/build && make -j"$(nproc)" 2>&1 | grep -iE "error|yabause.c|main.c|Built target yabause" | tail -15'
```
Expected: builds clean. If `MappedMemoryWriteLongNocache` / `MappedMemoryReadLongNocache` are not declared in yabause.c's includes, they live in memory.h (already included by yabause.c) — do not add includes unless the compiler names a missing symbol.

- [ ] **Step 5: Smoke-run (no crash on boot)**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv; timeout 8 build/src/gtk/yabause -b bios/saturn-jp-v100.bin --stvboot 2>&1 | tail -15; echo "ran"'
```
Expected: launches and runs ~8 s without an immediate fatal error/segfault. (Whether the game renders is verified in Task 2 + later M4 — here we only confirm StvBoot doesn't crash the emulator.)

- [ ] **Step 6: Commit**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv && git add yabause/src/yabause.c yabause/src/yabause.h yabause/src/gtk/main.c && git commit -m "feat(stv): StvBoot — seed master SH-2 into ST-V IP; --stvboot trigger"'
```

---

## Task 2: Verify execution reaches the ST-V IP (breakpoint PC probe)

**Files:**
- Modify: `/root/yabause-stv/yabause/src/yabause.c` (add an env-guarded breakpoint probe inside `StvBoot`)

**Interfaces:**
- Consumes: `SH2SetBreakpointCallBack(SH2_struct*, void(*)(void*,u32,void*), void*)`, `SH2AddCodeBreakpoint(SH2_struct*, u32)`, `MSH2->breakpointEnabled` (sh2core.h).
- Produces: stderr lines `[STV-BP] PC=........ hit#N` when guarded breakpoints fire.

- [ ] **Step 1: Add the breakpoint callback + probe**

Above `StvBoot`, add the callback:
```c
static void StvBpHit(UNUSED void *ctx, u32 addr, UNUSED void *data)
{
   static int n = 0;
   fprintf(stderr, "[STV-BP] PC=%08X hit#%d\n", addr, ++n);
}
```
At the END of `StvBoot` (after the register seed), add:
```c
   if (getenv("STV_PCTRACE")) {
      SH2SetBreakpointCallBack(MSH2, StvBpHit, NULL);
      SH2AddCodeBreakpoint(MSH2, 0x060249FE); // IP entry (we should hit this)
      SH2AddCodeBreakpoint(MSH2, 0x0604B446); // game-code entry (bonus: M4-ish)
      SH2AddCodeBreakpoint(MSH2, 0x06036DBC); // attract main loop (bonus)
      MSH2->breakpointEnabled = 1;
   }
```
Verify against sh2core.h whether `breakpointEnabled` is the correct enable flag and whether `SH2AddCodeBreakpoint` already sets it; adjust the enable line to match the actual API (check `SH2AddCodeBreakpoint`'s body in sh2core.c).

- [ ] **Step 2: Build**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv/build && make -j"$(nproc)" 2>&1 | grep -iE "error|Built target yabause" | tail'
```
Expected: builds clean.

- [ ] **Step 3: Run with the probe and confirm the IP entry is hit**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv; STV_PCTRACE=1 timeout 10 build/src/gtk/yabause -b bios/saturn-jp-v100.bin --stvboot 2>&1 | grep "\[STV-BP\]" | head -20'
```
Expected (minimum success): at least one `[STV-BP] PC=060249FE hit#…` line — proving the master SH-2 began executing the ST-V IP from our seeded entry. Record whether `0604B446` and/or `06036DBC` also appear (bonus: indicates the IP is progressing toward attract — likely partial until the M4 shims exist).

- [ ] **Step 4: If 0x060249FE is NOT hit — diagnose, don't fake**

If no breakpoint fires, the seed/run path is wrong. Check in order: (a) is `StvBoot` actually called (add a one-shot `fprintf(stderr,"[STV] StvBoot\\n")` at its top); (b) did the cart load (the M2 `STV_SELFTEST` still passes); (c) is `breakpointEnabled` the right flag / does the interpreter core honor breakpoints (Yabause has multiple SH2 cores — ensure `SH2Int` selects the interpreter, not a dynarec that may skip breakpoint checks). Report findings; this is a real result, not a failure to hide.

- [ ] **Step 5: Commit**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv && git add yabause/src/yabause.c && git commit -m "test(stv): breakpoint PC probe — confirm SH-2 reaches ST-V IP entry"'
```

---

## Self-Review

**Spec coverage (design spec M3):**
- ✅ Boot handoff so the Saturn-side reaches the ST-V game → Task 1 (StvBoot)
- ✅ Reuses the Phase-1-equivalent direct-seed mechanism (here as C, the trampoline's software twin) → Task 1
- ✅ IP copy CS0→HWRAM + entry seed per M0 → Task 1 Step 2
- ✅ Confirm execution arrival via breakpoint → Task 2

**Placeholder scan:** No TODOs. Task 2 Step 1 instructs verifying the exact breakpoint-enable API against sh2core.c — that is a real correctness check, not a placeholder; the code given is the intended implementation.

**Type consistency:** `StvBoot(void)` declared (Task 1 Step 1) and defined (Step 2) identically; `StvBpHit` matches the `void(*)(void*,u32,void*)` callback type required by `SH2SetBreakpointCallBack`.

**Known simplification (carry-forward):** StvBoot uses `YabauseSpeedySetup` (HLE) rather than running the real Saturn BIOS boot then cart-booting through it. This matches how Phase 1 validated (`--binary`) and is the pragmatic path to "execution in." Real Saturn-BIOS cart-boot (header overlay so the BIOS itself jumps in) is a possible later fidelity refinement, not needed for M3/M4.

**Out of scope (M4/M5):** IOGA (0x00400000) shim, 93C46 EEPROM (SMPC PDR) shim, input — the IP will likely stall/diverge when it first reads these; that is the M4 milestone.
