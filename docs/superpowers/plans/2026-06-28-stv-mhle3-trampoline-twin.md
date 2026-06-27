# M-HLE-3 Trampoline (Twin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot bakubaku to attract on the Yabause twin using the **real Saturn BIOS** (`-b saturn-jp-v100.bin`, NO `-a stv-jp-20091.bin`), via a `StvTrampoline()` that constructs the ST-V handoff state — proving the boot path is portable to real SAROO hardware (where the ST-V BIOS does not exist).

**Architecture:** A new `StvTrampoline()` (modeled on the existing snapshot-replay `StvBoot()`) constructs, from scratch, the machine state the game expects at boot: (1) the BIOS-resident HWRAM component (vector table + dispatch/pointer tables + resident handler code, ~12-16KB, extracted from a working boot), (2) the 8 low-address ST-V BIOS ROM routines, (3) the game image copied from CS0, (4) VDP/SCU/SCSP init, (5) sound 68k free-run, (6) SH-2 registers. Milestone M1 validates construction with ROM routines at their original low addresses; M2 relocates them off low memory (mask-ROM-faithful) by patching the resident blob's reference sites, removing all `<0x80000` execution dependency.

**Tech Stack:** C (Yabause core), `MappedMemory*Nocache` for state construction, `sh-elf-objdump` for SH-2 disasm, env-gated probes (`STV_*`), MAME 0.242 `bakubaku` as oracle.

## Global Constraints

- Source tree is **WSL `/root/yabause-stv`**; build dir `build/`, binary `build/src/gtk/yabause`. Edit WSL source via python scripts from scratchpad (multi-quote shells eat `\n`).
- `yabause/src/smpc.c` has **CRLF** line endings; `yabause.c`/`sh2int.c`/`scsp.c` are **LF**. Preserve per-file.
- Run config: `SH2Int=1` (debug interpreter, breakpoints), `VideoCore=2` (software, OGL segfaults under WSLg), `M68kInt=3` (Musashi, needed for sound 68k) in `~/.config/yabause/gtk/yabause.ini`.
- All new behavior **env-gated** (`STV_TRAMP`, etc.), inert by default — never change stock Yabause boot.
- Process kill: `pkill -9 -x yabause` (NOT `pkill -f yabause` — kills parent shell).
- Run with `MSYS_NO_PATHCONV=1` wrapper and `timeout` (binary never self-exits).
- Each milestone deliverable verified against MAME oracle (`/usr/games/mame bakubaku -rp /root/mame/roms`), not by unit tests — this is emulator behavioral work.
- Commit to WSL git per task; refresh bundle `/mnt/c/Users/mixio/Documents/GitHub/yabause-stv-fork.bundle` at milestone ends. Co-Author trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **IP note (deferred):** M1/M2 extract ST-V-BIOS-derived bytes as data blobs (fine for personal/research twin validation). A legal public real-hardware release may require clean reimplementation of the resident blob + routines (porting-doc option b) — out of scope for this plan, flagged for Phase 2.

**Reference docs:** `docs/superpowers/recon/2026-06-28-stv-bios-runtime-dependency-enumeration.md` (8 HLE routines), `docs/superpowers/recon/2026-06-28-stv-bios-boot-trampoline-spec.md` (handoff state + memory map), `docs/STV-HARDWARE-PORTING.md`.

---

## File Structure

- **Create** `yabause/src/stvtramp.c` — `StvTrampoline()` + helpers (state construction). Mirrors `StvBoot()` style.
- **Create** `yabause/src/stvtramp.h` — declares `void StvTrampoline(void)`.
- **Modify** `yabause/src/yabause.c` — call `StvTrampoline()` when `getenv("STV_TRAMP")`, after Saturn BIOS load, replacing the `-a`/`StvBoot` paths.
- **Modify** `yabause/src/CMakeLists.txt` (or the src build list) — add `stvtramp.c`.
- **Create** (data, gitignored) `stvstate/tramp/resident.bin` — extracted BIOS-resident HWRAM blob (0x06000000-0x0600FFFF).
- **Create** (data, gitignored) `stvstate/tramp/romroutines.bin` — extracted ST-V BIOS ROM region containing the 8 routines + callees.
- **Create** `tools/stv/extract_tramp.py` — extraction tooling (Task 0).
- **Create** `tools/stv/reloc_sites.py` — relocation reference-site analysis (Task 4).
- Reuse existing env-gated mechanisms in `smpc.c`, `scsp.c` (`ScspStvVectorWritten` sound 68k free-run), `vdp2.c`/`scu.c` writes.

---

## Milestone M1 — Construction validated (ROM routines at original low addresses)

Proves the trampoline can build the full handoff state and reach attract, with everything EXCEPT relocation. ROM routines placed at original `0x00000xxx`.

### Task 0: Extraction tooling — capture the resident blob + ROM routines

**Files:**
- Create: `tools/stv/extract_tramp.py`
- Produces (gitignored): `stvstate/tramp/resident.bin`, `stvstate/tramp/romroutines.bin`

**Interfaces:**
- Consumes: a working `-a` from-scratch boot (existing) + `STV_DUMPRAM` (HWRAM dump) + `bios/stv-jp-20091.bin`.
- Produces: `resident.bin` (0x10000 bytes = HWRAM 0x06000000-0x0600FFFF), `romroutines.bin` (0x8000 bytes = BIOS ROM 0x00000000-0x00008000, contains all 8 routines at 0xEFC-0x4596 + callees).

- [ ] **Step 1: Determine resident-blob stability window.** Dump HWRAM at 3 frames; diff the 0x06000000-0x0600F000 region for a stable pre-game-mutation frame.

```bash
cd /root/yabause-stv && mkdir -p stvstate/tramp
for fr in 60 120 250; do
  DISPLAY=:0 STV_BOOT=1 STV_DUMPRAM=$fr timeout 40 \
    ./build/src/gtk/yabause -b bios/stv-jp-20091.bin -a 2>/dev/null
  cp stvstate/fs_hwram.bin stvstate/tramp/hw_$fr.bin
done
python3 -c "
a=open('stvstate/tramp/hw_120.bin','rb').read()[:0xF000]
b=open('stvstate/tramp/hw_250.bin','rb').read()[:0xF000]
d=[i for i in range(len(a)) if a[i]!=b[i]]
print('resident diffs 120vs250:', len(d), 'first:', [hex(x) for x in d[:8]])"
```
Expected: few diffs, confined to work-var offsets (0x300-0xA14). Pick earliest stable frame (likely ~120) as `RESIDENT_FRAME`.

- [ ] **Step 2: Write `extract_tramp.py`.**

```python
#!/usr/bin/env python3
hw = open("stvstate/fs_hwram.bin", "rb").read()      # STV_DUMPRAM at RESIDENT_FRAME
open("stvstate/tramp/resident.bin", "wb").write(hw[0x0000:0x10000])
bios = open("bios/stv-jp-20091.bin", "rb").read()
open("stvstate/tramp/romroutines.bin", "wb").write(bios[0x0000:0x8000])
print("resident 0x%X, romroutines 0x8000" % len(hw[0x0000:0x10000]))
```

- [ ] **Step 3: Run extraction at RESIDENT_FRAME.**

```bash
DISPLAY=:0 STV_BOOT=1 STV_DUMPRAM=120 timeout 40 ./build/src/gtk/yabause -b bios/stv-jp-20091.bin -a 2>/dev/null
python3 tools/stv/extract_tramp.py
```
Expected: `resident 0x10000, romroutines 0x8000`.

- [ ] **Step 4: Verify blob contents.**

```bash
python3 -c "
import struct
d=open('stvstate/tramp/resident.bin','rb').read()
assert struct.unpack('>I',d[0:4])[0]==0x06002052, 'vec0'
assert d[0xF000:0xF004]==b'SEGA', 'game hdr'
b=open('stvstate/tramp/romroutines.bin','rb').read()
assert struct.unpack('>H',b[0xEFC:0xEFE])[0]==0x4F22, 'routine 0xEFC sts.l'
print('blob verify OK')"
```
Expected: `blob verify OK`.

- [ ] **Step 5: Commit.**

```bash
echo "stvstate/" >> .gitignore
git add tools/stv/extract_tramp.py .gitignore
git commit -m "feat(stv): M-HLE-3 trampoline extraction tooling

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 1: StvTrampoline skeleton — Saturn BIOS boot + game copy + resident blob

**Files:**
- Create: `yabause/src/stvtramp.c`, `yabause/src/stvtramp.h`
- Modify: `yabause/src/yabause.c`, src build list

**Interfaces:**
- Consumes: `MappedMemoryWriteLongNocache`, `MappedMemoryReadLongNocache`, `MSH2`, `YabauseResetNoLoad`, `YabauseSpeedySetup`; `resident.bin`, `romroutines.bin`; game mapped into CS0 by existing `StvLoadRoms`.
- Produces: `void StvTrampoline(void)`; entry for `STV_TRAMP=1`.

- [ ] **Step 1: Create `stvtramp.h`.**

```c
#ifndef STVTRAMP_H
#define STVTRAMP_H
void StvTrampoline(void);
#endif
```

- [ ] **Step 2: Create `stvtramp.c` — load resident blob + (placeholder) game copy.**

```c
#include "core.h"
#include "yabause.h"
#include "memory.h"
#include "sh2core.h"
#include "stvtramp.h"
#include <stdio.h>

static void load_blob(u32 dest, const char *path, u32 max) {
   FILE *f = fopen(path, "rb"); u32 i; unsigned char b[4];
   if (!f) { fprintf(stderr, "[TRAMP] MISSING %s\n", path); return; }
   for (i = 0; i < max; i += 4) { if (fread(b,1,4,f)!=4) break;
      MappedMemoryWriteLongNocache(MSH2, dest + i,
         ((u32)b[0]<<24)|((u32)b[1]<<16)|((u32)b[2]<<8)|b[3]); }
   fclose(f);
   fprintf(stderr, "[TRAMP] %s -> 0x%08X (0x%X bytes)\n", path, dest, i);
}

void StvTrampoline(void) {
   YabauseResetNoLoad();
   YabauseSpeedySetup();
   load_blob(0x06000000, "/root/yabause-stv/stvstate/tramp/resident.bin", 0x10000);
   /* game copy CS0 -> 0x0600F000 added in Step 4 (GAME_CS0_OFF measured first) */
}
```

- [ ] **Step 3: Wire into `yabause.c`.** Add `#include "stvtramp.h"`; in the boot path after `LoadBios(init->biospath)` succeeds: `if (getenv("STV_TRAMP")) { StvTrampoline(); }`. Add `stvtramp.c` to `yabause/src/CMakeLists.txt` SOURCES.

- [ ] **Step 4: Measure CS0 game source offset + complete copy.**

```bash
python3 -c "
import glob, struct
hw=open('stvstate/fs_hwram.bin','rb').read()
game=hw[0xF000:0xF040]
for fn in glob.glob('stvroms/bakubaku/*'):
    idx=open(fn,'rb').read().find(game)
    if idx>=0: print(fn,'off 0x%X'%idx)"
```
Record `GAME_CS0_OFF`. Then in `stvtramp.c` after the resident load:

```c
   { u32 i; for (i = 0; i < 0x90000; i += 4)
       MappedMemoryWriteLongNocache(MSH2, 0x0600F000 + i,
          MappedMemoryReadLongNocache(MSH2, 0x02000000 + GAME_CS0_OFF + i)); }
```

- [ ] **Step 5: Build + verify resident blob and game land in HWRAM (no -a).**

```bash
cd /root/yabause-stv/build && make -j$(nproc) 2>&1 | tail -3
cd /root/yabause-stv
DISPLAY=:0 STV_TRAMP=1 STV_DUMPRAM=2 timeout 20 ./build/src/gtk/yabause -b bios/saturn-jp-v100.bin 2>/tmp/t1.log
grep TRAMP /tmp/t1.log
python3 -c "
import struct
d=open('stvstate/fs_hwram.bin','rb').read()
print('vec0=0x%08X' % struct.unpack('>I',d[0:4])[0], 'hdr', d[0xF000:0xF004])"
```
Expected: `vec0=0x06002052 hdr b'SEGA'`, Saturn BIOS, no `-a`.

- [ ] **Step 6: Commit.**

```bash
git add yabause/src/stvtramp.c yabause/src/stvtramp.h yabause/src/yabause.c yabause/src/CMakeLists.txt
git commit -m "feat(stv): StvTrampoline skeleton -- resident blob + game copy (Saturn BIOS, no -a)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 2: ROM routines at low addresses (M1) + HW/sound/regs init

**Files:** Modify `yabause/src/stvtramp.c`, `yabause/src/scsp.c`

**Interfaces:**
- Consumes: `romroutines.bin`; `ScspStvVectorWritten()`; VDP2/SCU write helpers.
- Produces: complete handoff — `StvTrampoline()` reaches the game's first instruction.

- [ ] **Step 1: Load ROM routines at low addresses (M1 shortcut).**

```c
   /* (M1 only) ST-V BIOS ROM routines at original low addrs; M2 relocates. */
   load_blob(0x00000000, "/root/yabause-stv/stvstate/tramp/romroutines.bin", 0x8000);
```
Verify in Step 5 the master SH-2 reads these (the runtime enum saw plain `0x000xxxxx` targets).

- [ ] **Step 2: VDP2/SCU init to handoff values.**

```c
   MappedMemoryWriteWordNocache(MSH2, 0x05F80000, 0x8000);        /* TVMD DISP on */
   MappedMemoryWriteLongNocache(MSH2, 0x05FE00A0, 0xFFFFE1FC);    /* SCU IMS vblank unmasked */
```

- [ ] **Step 3: Sound 68k free-run — broaden the gate to STV_TRAMP.** In `scsp.c` change the two `ScspStvVectorWritten` gates from `getenv("STV_BOOT")` to `(getenv("STV_BOOT")||getenv("STV_TRAMP"))` via a CRLF-safe python patch script `tools/stv/patch_scsp_tramp.py`.

- [ ] **Step 4: Set SH-2 registers + entry.**

```c
   SH2GetRegisters(MSH2, &MSH2->regs);
   MSH2->regs.VBR = 0x06000000; MSH2->regs.SR.all = 0x000000F0;
   MSH2->regs.GBR = 0xFFFFFE00; MSH2->regs.R[15] = 0x060FFFF8;
   MSH2->regs.PC = STV_TRAMP_ENTRY;   /* measured in Step 5 */
   SH2SetRegisters(MSH2, &MSH2->regs);
```

- [ ] **Step 5: Measure `STV_TRAMP_ENTRY` + verify game executes.** Instrument the `-a` boot to log master PC just before the first execution of 0x0601270C; use that resident-code PC as entry.

```bash
cd /root/yabause-stv/build && make -j$(nproc) 2>&1 | tail -2
cd /root/yabause-stv
DISPLAY=:0 STV_TRAMP=1 STV_BIOSCALL=1 STV_PCSAMPLE=1 timeout 30 \
  ./build/src/gtk/yabause -b bios/saturn-jp-v100.bin 2>/tmp/t2.log
grep -E "BIOSCALL|\[H\]|\[PC\]" /tmp/t2.log | head -20
```
Expected: PC reaches game 0x0601xxxx; BIOSCALL shows the same 8 targets as the `-a` boot.

- [ ] **Step 6: Commit.**

```bash
git add yabause/src/stvtramp.c yabause/src/scsp.c tools/stv/patch_scsp_tramp.py
git commit -m "feat(stv): trampoline reaches game -- ROM routines(low,M1)+HW+sound+regs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 3: M1 milestone — attract renders under trampoline (Saturn BIOS, no -a)

**Files:** integration verification.

- [ ] **Step 1: Run to attract + screenshot.**

```bash
DISPLAY=:0 STV_TRAMP=1 STV_SHOT=4000 timeout 90 \
  ./build/src/gtk/yabause -b bios/saturn-jp-v100.bin 2>/tmp/m1.log
```

- [ ] **Step 2: Convert + compare to MAME oracle.**

```bash
python3 tools/stv/topng.py stvstate/frame_4000.ppm /tmp/m1_attract.png
```
Expected: leaf-field attract + sprites, nonblack ~63000+ (MAME f1300 = 63793). If black/partial, diff HWRAM+regs of the trampoline run vs the known-good `-a` boot at the same frame to find the missing construction step.

- [ ] **Step 3: Commit milestone + bundle.**

```bash
git add -A && git commit -m "milestone(stv): M1 -- attract renders under trampoline (no -a, Saturn BIOS)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git bundle create /mnt/c/Users/mixio/Documents/GitHub/yabause-stv-fork.bundle --all
```

---

## Milestone M2 — Relocation (mask-ROM-faithful, zero low-address dependency)

Removes the M1 low-address shortcut: ROM routines move to a high free region; resident-blob reference sites patched to point there. After M2 the master SH-2 never executes `<0x80000` — the exact constraint real Saturn imposes.

### Task 4: Enumerate relocation reference sites

**Files:** Create `tools/stv/reloc_sites.py`; modify `yabause/src/sh2int.c`.

**Interfaces:**
- Consumes: running M1 trampoline; resident blob.
- Produces: list of every site yielding a `<0x80000` address (HWRAM pointer slots + hardcoded ROM-pointer reads) for M2 to patch.

- [ ] **Step 1: Extend BIOSCALL to log pointer provenance.** On each new game->BIOS target `cur<0x80000`, scan resident regions 0x06000300-0x06000A14 for a long `==cur` and log `slot=0x060006xx holds target=cur`; if none, log `target=cur NO-SLOT (hardcoded)`.

- [ ] **Step 2: Run + collect.**

```bash
cd /root/yabause-stv/build && make -j$(nproc) 2>&1 | tail -2
cd /root/yabause-stv
DISPLAY=:0 STV_TRAMP=1 STV_BIOSCALL=1 timeout 90 \
  ./build/src/gtk/yabause -b bios/saturn-jp-v100.bin 2>/tmp/reloc.log
grep -E "slot=|NO-SLOT" /tmp/reloc.log | sort -u
```
Expected: each of the 8 routines mapped to a resident slot OR flagged NO-SLOT (e.g. 0x06000D2E's `[0x000010E8]`).

- [ ] **Step 3: Write `reloc_sites.py` — emit patch table.**

```python
#!/usr/bin/env python3
RELOC_BASE = 0x060E0000
import re
sites=set()
for line in open("/tmp/reloc.log"):
    m=re.search(r"slot=(\w+) holds target=(\w+)", line)
    if m: sites.add((int(m.group(1),16), int(m.group(2),16)))
for slot,old in sorted(sites):
    print(f"{{ 0x{slot:08X}, 0x{old:08X} }},  /* -> 0x{RELOC_BASE+old:08X} */")
```

- [ ] **Step 4: Commit.**

```bash
git add tools/stv/reloc_sites.py yabause/src/sh2int.c
git commit -m "feat(stv): enumerate ROM-routine relocation reference sites (M2 prep)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 5: Relocate routines + patch references; remove low-address load

**Files:** Modify `yabause/src/stvtramp.c`.

**Interfaces:**
- Consumes: `reloc_sites.py` patch table; `romroutines.bin`.
- Produces: trampoline with routines at `RELOC_BASE`, refs patched, NO `0x00000000` load.

- [ ] **Step 1: Load routines at RELOC_BASE instead of 0.** Replace Task-2 Step-1:

```c
   #define STV_RELOC_BASE 0x060E0000u
   load_blob(STV_RELOC_BASE, "/root/yabause-stv/stvstate/tramp/romroutines.bin", 0x8000);
```

- [ ] **Step 2: Patch resident pointer slots.**

```c
   static const struct { u32 slot; u32 old; } reloc[] = {
      /* paste reloc_sites.py output here, e.g.: */
      { 0x06000640, 0x00003744 }, { 0x06000A08, 0x000044FC },
      { 0x06000A0C, 0x000044FC }, { 0x06000A10, 0x000044FC },
   };
   for (unsigned k=0;k<sizeof(reloc)/sizeof(reloc[0]);k++)
      MappedMemoryWriteLongNocache(MSH2, reloc[k].slot, STV_RELOC_BASE + reloc[k].old);
```

- [ ] **Step 3: Patch hardcoded ROM-pointer reads.** For NO-SLOT routines (e.g. 0x06000D2E reads `[0x000010E8]`), disasm to find the literal-pool address feeding the read, then redirect it + seed the relocated pointer:

```bash
sh-elf-objdump -D -b binary -m sh2 -EB --adjust-vma=0x06000000 \
  --start-address=0x06000D14 --stop-address=0x06000D40 stvstate/tramp/resident.bin
```
```c
   MappedMemoryWriteLongNocache(MSH2, /*literal-pool addr*/ , STV_RELOC_BASE + 0x10E8);
   MappedMemoryWriteLongNocache(MSH2, STV_RELOC_BASE + 0x10E8, STV_RELOC_BASE + 0x00000EFC);
```

- [ ] **Step 4: Build + assert zero low-address execution.** Add `STV_NOLOW` probe in sh2int.c: log `LOWPC` if master PC `<0x80000`. Run:

```bash
cd /root/yabause-stv/build && make -j$(nproc) 2>&1 | tail -2
cd /root/yabause-stv
DISPLAY=:0 STV_TRAMP=1 STV_NOLOW=1 STV_SHOT=4000 timeout 90 \
  ./build/src/gtk/yabause -b bios/saturn-jp-v100.bin 2>/tmp/m2.log
grep -c LOWPC /tmp/m2.log
```
Expected: `0` low-address executions; attract still renders.

- [ ] **Step 5: Commit.**

```bash
git add yabause/src/stvtramp.c yabause/src/sh2int.c
git commit -m "feat(stv): relocate ROM routines off low memory + patch refs (mask-ROM-faithful)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 6: M2 milestone — full play under trampoline + portability assertion

**Files:** integration (reuse `STV_AUTOPLAY`); update `docs/STV-HARDWARE-PORTING.md`.

- [ ] **Step 1: Full run to STAGE 1 with autoplay, zero low exec.**

```bash
DISPLAY=:0 STV_TRAMP=1 STV_AUTOPLAY=1 STV_NOLOW=1 STV_SHOT="8500,10500,11500" \
  timeout 200 ./build/src/gtk/yabause -b bios/saturn-jp-v100.bin 2>/tmp/m2play.log
grep -c LOWPC /tmp/m2play.log
python3 tools/stv/topng.py stvstate/frame_11500.ppm /tmp/m2_stage1.png
```
Expected: STAGE 1 reached + played (matches v4), `0` low-address exec, Saturn BIOS only.

- [ ] **Step 2: Update porting doc.** Record in `docs/STV-HARDWARE-PORTING.md` B/C: trampoline twin-validated; resident-blob size 0x10000; RELOC_BASE; patch-site count — the recipe Phase 2 (FPGA/STM32) implements.

- [ ] **Step 3: Commit milestone + bundle + memory.**

```bash
git add -A && git commit -m "milestone(stv): M2 -- bakubaku fully playable under trampoline, zero low-addr exec

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git bundle create /mnt/c/Users/mixio/Documents/GitHub/yabause-stv-fork.bundle --all
```
Update saroo memory: M-HLE-3 twin complete = real-hardware-portable boot path proven; next = Phase 2 (FPGA ROM map + IOGA, STM32 input, trampoline port to cart).

---

## Self-Review Notes

- **Spec coverage:** trampoline spec's 5 steps → Task 1 (resident+game), Task 2 (ROM routines+HW+sound+regs); runtime 8-routine HLE list → reached as relocated ROM routines (Tasks 2/5), not hand-reimplemented (extracted; clean reimpl deferred per IP note). Handoff invariants → Task 2 Step 4. Portability assertion (no low exec) → Task 5/6 `STV_NOLOW`.
- **Empirical placeholders are intentional:** `RESIDENT_FRAME`, `GAME_CS0_OFF`, `STV_TRAMP_ENTRY`, the reloc patch table, and the 0x06000D2E literal-pool address are measured in their own steps (commands + expected output provided) rather than guessed — this is reverse-engineering; the measurement IS the task.
- **Two-stage de-risk:** M1 isolates construction (all but relocation); M2 isolates relocation. A reviewer can reject M2 while keeping M1.
