# ST-V BIOS HLE — M-HLE-0 Recon + M-HLE-1 State Reproduction Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use `- [ ]` tracking. (Agent dispatch has been unavailable this session; inline execution via executing-plans is the working fallback.)

**Goal:** Pin the exact ST-V-BIOS→game handoff point and trace the game's runtime ST-V-BIOS/peripheral dependencies (M-HLE-0); then capture the handoff machine state from MAME and reproduce it in the Yabause bridge so the master SH-2 runs the game's own code **past** the fill loop where M3 got stuck (M-HLE-1).

**Architecture:** MAME `stv bakubaku` is the reference oracle. At the deterministic handoff PC `0x0604B446` (first hit), dump HWRAM + LWRAM + master SH-2 registers to files. `StvBoot` loads those files (writes RAM via `MappedMemoryWriteLongNocache`, sets registers via `SH2SetRegisters`) instead of the current naive copy, then runs. Reproducing the captured registers (esp. the fill-loop count R4) + RAM lets the game continue correctly from handoff. VDP/SCU/SMPC capture is deferred to M-HLE-2 unless M-HLE-1 shows it is needed.

**Tech Stack:** MAME 0.242 (`-debug`/`-debugscript` or Lua) in WSL; C (yabause.c StvBoot, file I/O); built GTK port; software renderer; PC sampler (`STV_PCSAMPLE`) + breakpoint probe (`STV_PCTRACE`) for verification.

## Global Constraints

- All Linux commands via `wsl.exe bash -lc "…"` (Bash tool is Git Bash on Windows).
- MAME roms at `/root/mame/roms` (default rompath); BIOS `-bios jp1` (= EPR-20091, Japan); game `bakubaku`.
- Yabause fork: `/root/yabause-stv/yabause/src/`; build `cd /root/yabause-stv/build && make -j$(nproc)`; binary `build/src/gtk/yabause`; run with `SH2Int=1` (debug interp, breakpoints), `VideoCore=2` (software), JP Saturn BIOS, `CartType=12`, `--stvboot`.
- Handoff PC (deterministic capture point): `0x0604B446` (first hit). Attract main loop: `0x06036DBC`. Game-image load mapping (verified): `fpr[k] -> HWRAM[k + 0x0600F000]`.
- HWRAM range `0x06000000`–`0x060FFFFF` (1 MB). LWRAM range `0x00200000`–`0x002FFFFF` (1 MB).
- State files live under `/root/yabause-stv/stvstate/` (git-ignored; not committed — derived from copyrighted ROM).
- Recon output: `docs/superpowers/recon/2026-06-25-stv-bios-hle-recon.md` (this repo).
- Do NOT add IOGA/EEPROM/service HLE here — that is M-HLE-2.

---

## Task 1: M-HLE-0 — pin handoff + trace runtime dependencies

**Files:**
- Create: `docs/superpowers/recon/2026-06-25-stv-bios-hle-recon.md` (this repo)
- Create (WSL, working): `/tmp/handoff_trace.lua`

**Interfaces:**
- Produces (consumed by M-HLE-1 / M-HLE-2): a doc with (a) `HANDOFF` — confirmation that the first `maincpu` PC == `0x0604B446` is deterministic, the frame it occurs, and the master SH-2 register values there; (b) `RUNTIME_READS` — every access between handoff and attract to: BIOS ROM (`0x00000000`–`0x0007FFFF`, i.e. service calls), IOGA (`0x00400000`+), SMPC (`0x00100000`+, EEPROM bit-bang), and LWRAM (`0x00200000`+) — so we know what the captured state must include and which services M-HLE-2 must HLE.

- [ ] **Step 1: Confirm the handoff PC is deterministic + capture its registers**

Write `/tmp/handoff_trace.lua`:
```lua
local done=false
emu.register_frame_done(function()
  if done then return end
  local cpu=manager.machine.devices[":maincpu"]
  local function st(n) local s=cpu.state[n]; return s and s.value or -1 end
  if st("PC")==0x0604B446 then
    io.stderr:write(string.format("HANDOFF frame=? PC=0604B446\n"))
    for _,r in ipairs({"R0","R1","R2","R3","R4","R5","R6","R7","R8","R9","R10","R11","R12","R13","R14","R15","PR","SR","GBR","VBR","MACH","MACL"}) do
      io.stderr:write(string.format("  %-4s=%08X\n",r,st(r)))
    end
    done=true
  end
end)
```
Run:
```bash
wsl.exe bash -lc 'cp /mnt/c/.../handoff_trace.lua /tmp/; mame bakubaku -bios jp1 -video none -autoboot_script /tmp/handoff_trace.lua -seconds_to_run 30 2>&1 | grep -E "HANDOFF|R[0-9]|PR|SR|GBR|VBR|MAC"'
```
Expected: the register dump prints. Run twice; confirm R4 (the fill-loop count) and the others are **identical** across runs (determinism). Record the values.

- [ ] **Step 2: Trace runtime reads from handoff to attract**

Use MAME's debugger to watch the relevant regions after handoff. Write `/tmp/runtime.txt` (debugscript):
```
bpset 0x0604B446,1,{ wpset 0x00000000,0x80000,r,1,{ printf "BIOSrd @%08X pc=%08X\n",wpaddr,pc; g } ; wpset 0x00400000,0x40,r,1,{ printf "IOGArd @%08X pc=%08X\n",wpaddr,pc; g } ; g }
g
```
Run:
```bash
wsl.exe bash -lc 'mame bakubaku -bios jp1 -debug -debugscript /tmp/runtime.txt -seconds_to_run 30 > /tmp/rt.log 2>&1 || true; grep -E "BIOSrd|IOGArd" /tmp/rt.log | sed -E "s/ pc=.*//" | sort | uniq -c | sort -rn | head -40'
```
Expected: a deduplicated list of BIOS-ROM service addresses and IOGA addresses the game touches after handoff. (If the `-debug` headless path misbehaves under WSL, fall back to a Lua per-frame poll of these regions. Record whichever works.) Also widen one run to watch SMPC `0x00100000,0x80` for the EEPROM bit-bang.

- [ ] **Step 3: Write the recon doc**

Create `docs/superpowers/recon/2026-06-25-stv-bios-hle-recon.md` with sections:
- `## HANDOFF` — PC `0x0604B446`, deterministic (yes/no), register values (table), frame.
- `## RUNTIME_READS` — tables of BIOS-ROM service addresses, IOGA addresses, SMPC/EEPROM accesses, and whether any LWRAM reads occur (=> LWRAM must be captured).
- `## CAPTURE_SET` — conclusion: capture HWRAM + master SH-2 regs always; capture LWRAM iff Step 2 shows LWRAM reads; note VDP/SCU deferred to M-HLE-2.

- [ ] **Step 4: Commit**
```bash
cd /c/Users/mixio/Documents/GitHub/SAROO-STV
git add docs/superpowers/recon/2026-06-25-stv-bios-hle-recon.md
git commit -m "docs(recon): ST-V BIOS HLE — handoff PC + runtime dependency trace"
```

---

## Task 2: M-HLE-1a — MAME capture script (handoff state -> files)

**Files:**
- Create (WSL): `/root/yabause-stv/tools/capture_handoff.lua` (or a debugscript) + the output dir `/root/yabause-stv/stvstate/`

**Interfaces:**
- Consumes: HANDOFF PC `0x0604B446` and CAPTURE_SET from Task 1.
- Produces: `stvstate/hwram.bin` (1 MB, `0x06000000`–`0x060FFFFF`), `stvstate/lwram.bin` (1 MB, if Task 1 says needed), `stvstate/regs.txt` (master SH-2 registers, one `NAME=HEX` per line). These are loaded by Task 3.

- [ ] **Step 1: Dump memory + registers at the handoff via the MAME debugger**

The MAME debugger `save <file>,<addr>,<len>` dumps a memory range. Write `/tmp/capture.txt`:
```
bpset 0x0604B446,1,{ save /root/yabause-stv/stvstate/hwram.bin,0x06000000,0x100000 ; save /root/yabause-stv/stvstate/lwram.bin,0x00200000,0x100000 ; printf "R4=%08X R15=%08X PR=%08X GBR=%08X VBR=%08X SR=%08X\n",r4,r15,pr,gbr,vbr,sr }
g
```
Run:
```bash
wsl.exe bash -lc 'mkdir -p /root/yabause-stv/stvstate; mame bakubaku -bios jp1 -debug -debugscript /tmp/capture.txt -seconds_to_run 30 > /tmp/cap.log 2>&1 || true; ls -l /root/yabause-stv/stvstate/; grep -E "R4=" /tmp/cap.log'
```
Expected: `hwram.bin` (1048576 bytes) and `lwram.bin` (1048576 bytes) exist; the register line prints. (If `save` halts emulation differently, ensure the `g` keeps running until the bp fires.)

- [ ] **Step 2: Record the full register set to regs.txt**

Extend the debugscript action to print ALL registers (R0–R15, PR, SR, GBR, VBR, MACH, MACL) in `NAME=HEX` form, redirect the matching grep to `stvstate/regs.txt`:
```bash
wsl.exe bash -lc 'grep -oE "[A-Z0-9]+=[0-9A-F]{8}" /tmp/cap.log > /root/yabause-stv/stvstate/regs.txt; cat /root/yabause-stv/stvstate/regs.txt'
```
(Adjust the printf in capture.txt to emit every register if Step 1 only emitted a subset.) Expected: `regs.txt` has 22 `NAME=HEX` lines.

- [ ] **Step 3: Sanity-check the capture vs MAME ground truth**
```bash
wsl.exe bash -lc 'python3 -c "d=open(\"/root/yabause-stv/stvstate/hwram.bin\",\"rb\").read(); print(\"0x0604B440:\",d[0x4B440:0x4B448].hex()); print(\"expect 62637604 225274ff\")"'
```
Expected: `0x0604B440` bytes = `62637604225274ff` (matches the MAME game code). Confirms the dump captured the loaded game.

---

## Task 3: M-HLE-1b — StvBoot loads the captured state; verify progression

**Files:**
- Modify: `/root/yabause-stv/yabause/src/yabause.c` (`StvBoot`: replace the naive copy with a state-file load)

**Interfaces:**
- Consumes: `stvstate/hwram.bin`, `stvstate/lwram.bin`, `stvstate/regs.txt` from Task 2.
- Produces: a `StvBoot` that reproduces the captured handoff state, so the master SH-2 executes the game's own code past the fill loop.

- [ ] **Step 1: Replace StvBoot's load body with a state-file loader**

In `StvBoot` (yabause.c), replace the fpr-copy + fixed register seed with: ResetNoLoad + SpeedySetup, then load `hwram.bin` into `0x06000000` and `lwram.bin` into `0x00200000` via `MappedMemoryWriteLongNocache`, then parse `regs.txt` and set every register via `SH2SetRegisters`. Concrete code:
```c
static u32 stv_hex(const char *s){ return (u32)strtoul(s, NULL, 16); }

void StvBoot(void)
{
   FILE *f; u32 i, v; char line[64];
   YabauseResetNoLoad();
   YabauseSpeedySetup();

   // Load captured HWRAM (1MB) -> 0x06000000
   f = fopen("/root/yabause-stv/stvstate/hwram.bin", "rb");
   if (f) { for (i = 0; i < 0x100000; i += 4) { if (fread(&v,4,1,f)!=1) break;
            /* file is big-endian dump; bytes already in memory order */
            MappedMemoryWriteLongNocache(MSH2, 0x06000000 + i, __builtin_bswap32(v)); } fclose(f); }

   // Load captured LWRAM (1MB) -> 0x00200000 (skip if file absent)
   f = fopen("/root/yabause-stv/stvstate/lwram.bin", "rb");
   if (f) { for (i = 0; i < 0x100000; i += 4) { if (fread(&v,4,1,f)!=1) break;
            MappedMemoryWriteLongNocache(MSH2, 0x00200000 + i, __builtin_bswap32(v)); } fclose(f); }

   // Set registers from regs.txt (lines NAME=HEX)
   SH2GetRegisters(MSH2, &MSH2->regs);
   f = fopen("/root/yabause-stv/stvstate/regs.txt", "rb");
   if (f) { while (fgets(line, sizeof line, f)) {
        char *eq = strchr(line, '='); if (!eq) continue; *eq = 0; u32 val = stv_hex(eq+1);
        if (line[0]=='R') { int n = atoi(line+1); if (n>=0 && n<16) MSH2->regs.R[n]=val; }
        else if (!strcmp(line,"PC")) MSH2->regs.PC=val;
        else if (!strcmp(line,"PR")) MSH2->regs.PR=val;
        else if (!strcmp(line,"SR")) MSH2->regs.SR.all=val;
        else if (!strcmp(line,"GBR")) MSH2->regs.GBR=val;
        else if (!strcmp(line,"VBR")) MSH2->regs.VBR=val;
        else if (!strcmp(line,"MACH")) MSH2->regs.MACH=val;
        else if (!strcmp(line,"MACL")) MSH2->regs.MACL=val;
      } fclose(f); }
   MSH2->regs.PC = 0x0604B446;   // handoff entry
   SH2SetRegisters(MSH2, &MSH2->regs);

   if (getenv("STV_PCTRACE")) {
      SH2SetBreakpointCallBack(MSH2, StvBpHit, NULL);
      SH2AddCodeBreakpoint(MSH2, 0x0604B446);
      SH2AddCodeBreakpoint(MSH2, 0x06036DBC);
      MSH2->breakpointEnabled = 1;
   }
}
```
(The `regs.txt` byte order: the MAME debugger printf emits big-endian hex values directly, so `stv_hex` gives the correct register value — no swap. The `hwram.bin`/`lwram.bin` swap: `save` writes memory bytes in address order; reading 4 bytes into a u32 on little-endian host then `MappedMemoryWriteLongNocache` (which expects a host-order long it stores big-endian) — verify the endianness in Step 3 and drop/keep the `bswap32` to make the readback match.)

- [ ] **Step 2: Build**
```bash
wsl.exe bash -lc 'cd /root/yabause-stv/build && make -j"$(nproc)" 2>&1 | grep -iE "error|Built target yabause" | tail -3'
```
Expected: builds clean (ensure `<stdio.h>/<stdlib.h>/<string.h>` are included in yabause.c; add if the compiler complains).

- [ ] **Step 3: Verify the RAM load is byte-correct**

Reuse the M2-style live self-check: temporarily log `StvCs0`-independent HWRAM readback right after load — read `0x0604B440` via `MappedMemoryReadLongNocache(MSH2,0x0604B440)` and assert it equals `0x62637604`:
```c
      if (getenv("STV_SELFTEST"))
         fprintf(stderr, "[STV] HWRAM 0x0604B440 = %08X (expect 62637604)\n",
                 MappedMemoryReadLongNocache(MSH2, 0x0604B440));
```
Run `STV_SELFTEST=1 … --stvboot` and confirm `= 62637604`. If it is byte-swapped, flip the `bswap32` in Step 1 and rebuild until it matches.

- [ ] **Step 4: Verify the SH-2 progresses past the fill loop**
```bash
wsl.exe bash -lc 'cd /root/yabause-stv; STV_PCSAMPLE=1 STV_PCTRACE=1 timeout 15 build/src/gtk/yabause -b bios/saturn-jp-v100.bin --stvboot 2>/tmp/h1.log; echo "BP:"; grep "\[STV-BP\]" /tmp/h1.log | sort | uniq -c; echo "PC dist:"; grep "\[PC\]" /tmp/h1.log | sed "s/.*\[PC\] //" | sort | uniq -c | sort -rn | head'
```
Expected (M-HLE-1 success): the PC sampler shows PCs **beyond** the M3 stuck loop `0x0604B442-0x0604B44A` — i.e. the fill loop now terminates (correct R4) and execution moves on. Reaching `0x06036DBC` is the M-HLE-2 goal, not required here; reaching new game PCs past the fill loop is M-HLE-1 success. Record the observed trajectory.

- [ ] **Step 5: Commit**
```bash
wsl.exe bash -lc 'cd /root/yabause-stv && git add yabause/src/yabause.c && git commit -m "feat(stv): StvBoot reproduces captured handoff state (RAM+regs); past fill loop"'
```

---

## Self-Review

**Spec coverage (M-HLE-0 + M-HLE-1):**
- ✅ Pin handoff PC + determinism → Task 1 Step 1
- ✅ Trace runtime BIOS-service/IOGA/EEPROM/LWRAM deps → Task 1 Step 2 (feeds M-HLE-2 + the capture set)
- ✅ Minimal capture set decision → Task 1 Step 3 (CAPTURE_SET)
- ✅ MAME capture of handoff state to files → Task 2
- ✅ StvBoot reproduces state (RAM + regs) → Task 3 Step 1
- ✅ Verify progression past the fill loop → Task 3 Step 4
- ✅ Verification is state/trajectory-based (no pixel screenshot) → Task 3 Step 4

**Placeholder scan:** the `/mnt/c/.../handoff_trace.lua` path in Task 1 Step 1 is the scratch copy source — substitute the real scratchpad path at run time; not a logic placeholder. All code blocks are complete.

**Endianness:** Task 3 Step 1 flags the one real unknown (dump byte order) and Step 3 is the concrete test that resolves it before relying on it — not left to chance.

**Out of scope (M-HLE-2, next plan):** IOGA shim, 93C46 EEPROM, BIOS-service trap+HLE, reaching `0x06036DBC` attract loop, VDP/SCU state capture if needed.
