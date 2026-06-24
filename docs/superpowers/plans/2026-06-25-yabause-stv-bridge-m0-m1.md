# Yabause ST-V Bridge — M0 Recon + M1 Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the concrete "bridge spec" for `bakubaku` (entry point, IC→address map, ST-V init sequence, 315-5649 I/O map, 93C46 EEPROM behavior) by empirically running it in MAME's `stv` driver, and stand up a buildable/runnable vanilla Yabause baseline in WSL2 — the two prerequisites that unblock the M2–M5 bridge implementation.

**Architecture:** M0 uses MAME (which already emulates ST-V perfectly) as a known-good reference: run `bakubaku`, screenshot to confirm the dumps are good, and use MAME's scripted debugger to capture the master SH-2 entry PC and log A-Bus I/O + EEPROM accesses during boot→attract. M1 clones vanilla Yabause, builds the SDL port in WSL2, and boots the JP Saturn BIOS under WSLg to prove the baseline before any bridge code exists.

**Tech Stack:** MAME (`stv` driver) + Lua/`-debugscript`; vanilla Yabause SDL port; WSL2 Ubuntu 22.04 + WSLg; CMake/gcc; assets in `C:\Users\mixio\Downloads\`.

## Global Constraints

- Base emulator for the bridge: **vanilla Yabause, SDL port** (not Qt, not Kronos unless escalated).
- Build + run host: **WSL2 Ubuntu**, display via **WSLg**. Clone Yabause inside the WSL home filesystem (`~/`), NOT under `/mnt/c` (build performance).
- Saturn region for everything: **Japan (J)** — `bakubaku` header `0x40='J'`; use JP Saturn BIOS (v1.00 1994) and JP ST-V BIOS.
- MAME reference driver: **`bakubaku`** (parent BIOS set `stvbios`).
- Asset source paths (Windows): ST-V BIOS `C:\Users\mixio\Downloads\stvbios.zip`; game `C:\Users\mixio\Downloads\bakubaku.zip`; Saturn BIOS `C:\Users\mixio\Downloads\Sega Saturn BIOS v1.00 (1994)(Sega)(JP)(M6).zip`. WSL equivalents under `/mnt/c/Users/mixio/Downloads/`.
- Recon output doc lives in this repo: `docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md`.
- ST-V BIOS is a **reference only** — never loaded into Yabause's BIOS slot (stock-Saturn fidelity is the whole point).
- This plan does NOT touch the M2–M5 bridge code; that is a follow-on plan written after M0 completes.

---

## Task 1: M0 — Recon, produce the bakubaku bridge spec

**Files:**
- Create: `docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md` (this repo)
- Create (WSL, working): `~/stv-recon/bakubaku-stripchk.lua`, `~/stv-recon/trace.txt`, `~/stv-recon/*.png`

**Interfaces:**
- Produces (consumed by the M2–M5 plan): a markdown doc with these filled sections — `IC_MAP` (each IC file → A-Bus byte offset + length), `ENTRY` (master SH-2 PC at first instruction of game/cart code + whether code runs from cart `0x02xxxxxx` or copied to HWRAM `0x06xxxxxx`), `INIT` (ordered list of ST-V/SCU/A-Bus setup the game assumes before its entry), `IO_MAP` (315-5649 register addresses the game reads/writes during boot→attract, with the values that let boot proceed), `EEPROM` (93C46 access pattern + the bytes the game expects to read back).

- [ ] **Step 1: Verify MAME is present in WSL and locate its rompath**

Run (WSL):
```bash
which mame && mame -showconfig 2>/dev/null | grep -E '^\s*rompath'
```
Expected: a `mame` path prints, and a `rompath` line prints (note the first directory — call it `$ROMPATH`). If `mame` is missing, install it: `sudo apt-get install -y mame` (then re-run).

- [ ] **Step 2: Stage the ST-V romsets into MAME's rompath**

Run (WSL — substitute the real `$ROMPATH` from Step 1):
```bash
ROMPATH=~/.mame/roms        # or the first dir reported in Step 1; mkdir if needed
mkdir -p "$ROMPATH"
cp "/mnt/c/Users/mixio/Downloads/stvbios.zip"  "$ROMPATH/"
cp "/mnt/c/Users/mixio/Downloads/bakubaku.zip" "$ROMPATH/"
mame -verifyroms bakubaku
```
Expected: `romset bakubaku [stvbios] is good` (or `is best available`). If it reports BAD, stop — the dumps or rompath are wrong; do not proceed.

- [ ] **Step 3: Boot bakubaku in MAME and confirm the dumps reach attract mode**

Run (WSL):
```bash
mkdir -p ~/stv-recon && cd ~/stv-recon
mame bakubaku -video none -seconds_to_run 30 -snapname final -snapshot 2>&1 | tail -5
# headless run to ~attract, then snapshot:
mame bakubaku -seconds_to_run 25 -nothrottle -str 25 2>/dev/null || true
```
Then capture a screenshot after attract is reached:
```bash
mame bakubaku -autoboot_delay 20 -autoboot_command "" -snapname baku_attract &
sleep 30 ; ls -l ~/.mame/snap/bakubaku/ 2>/dev/null || find ~ -name 'baku*.png' 2>/dev/null
```
Expected: a PNG showing the Baku Baku Animal title / attract screen. (If using the MAME MCP instead: `mame_launch bakubaku`, `mame_run_frames 1500`, `mame_screenshot`.) Confirm visually the game runs — this proves BIOS+ROM are good and gives the reference "correct" picture.

- [ ] **Step 4: Capture the master SH-2 entry PC via a debug script**

Create `~/stv-recon/entry.txt` with MAME debugger commands:
```
focus maincpu
bpset 0x6000000,1,{ printf "HWRAM-entry PC=%08X R15=%08X\n",pc,r15 ; go }
bpset 0x2000000,1,{ printf "CART-entry  PC=%08X R15=%08X\n",pc,r15 ; go }
go
```
Run (WSL):
```bash
cd ~/stv-recon
mame bakubaku -debug -debugscript entry.txt -seconds_to_run 15 > entry_log.txt 2>&1 || true
grep -E 'entry' entry_log.txt | head
```
Expected: at least one `CART-entry` or `HWRAM-entry` line with a concrete PC. The FIRST such hit after BIOS hand-off is the game entry. Record it. (Note: bakubaku's cart maps at SH-2 `0x02000000`; if the game executes in place, entry is `0x02xxxxxx`; if BIOS copies it to work RAM, entry is `0x06xxxxxx`. Capture which, and the source it was copied from.)

- [ ] **Step 5: Extract the IC→A-Bus address map from MAME source**

Run (WSL):
```bash
cd ~/stv-recon
curl -fsSL https://raw.githubusercontent.com/mamedev/mame/master/src/mame/sega/stv.cpp -o stv.cpp || \
curl -fsSL https://raw.githubusercontent.com/mamedev/mame/master/src/mame/drivers/stv.cpp -o stv.cpp
grep -nE 'bakubaku|ROM_REGION|ROM_LOAD|cart' stv.cpp | grep -A12 -i bakubaku | head -40
```
Expected: the `bakubaku` `ROM_START`/`ROM_LOAD16_WORD_SWAP` block showing each `fpr17969.13`/`mpr179xx` with its load offset into the `"cart"` region. Record each file → offset → length. Cross-check the count/sizes against `unzip -l bakubaku.zip` (1×1MB + 4×4MB). Also note how the `"cart"` region maps into the SH-2/A-Bus space (the driver's `map(0x02000000,...)`).

- [ ] **Step 6: Log the 315-5649 I/O and 93C46 EEPROM accesses during boot→attract**

Find the I/O + EEPROM address ranges in the driver, then watch them:
```bash
cd ~/stv-recon
grep -nE '5649|eeprom|93c46|ioga|0x[0-9a-f]*0001|protbank|0x00400000|0x0040007|read_xb|ioport' stv.cpp | head -40
```
Create `~/stv-recon/iowatch.txt` (substitute the real I/O base/range found above; `0x00400000` region is the typical ST-V I/O area — confirm from the grep):
```
focus maincpu
wpset 0x400000,0x80,rw,1,{ printf "IO %s @%08X = %04X  (pc=%08X)\n", (wpdata?"WR":"RD"), wpaddr, wpdata, pc ; go }
go
```
Run:
```bash
mame bakubaku -debug -debugscript iowatch.txt -seconds_to_run 25 > iolog.txt 2>&1 || true
sort iolog.txt | uniq -c | sort -rn | head -40
```
Expected: a deduplicated list of the I/O/EEPROM addresses the game touches before attract, with read values. Record the addresses + the values the game must read back for boot to proceed (e.g. "no coin", region/dipsw bits, EEPROM magic). This is the minimum the M4 shims must reproduce.

- [ ] **Step 7: Write the bridge spec doc**

Create `docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md` with five filled sections, each populated from the steps above (no blanks):

```markdown
# bakubaku Bridge Spec (from MAME stv reference)

## IC_MAP            (Step 5)
| file | cart offset | length | A-Bus address |
|------|-------------|--------|---------------|
| fpr17969.13 | 0x...... | 0x100000 | 0x02000000 |
| mpr17970.2  | 0x...... | 0x400000 | 0x........ |
| ... | | | |

## ENTRY             (Step 4)
- Master SH-2 entry PC: 0x........
- Runs from: [cart 0x02xxxxxx | HWRAM 0x06xxxxxx copied from 0x........]
- Slave SH-2 at entry: [halted | 0x........]

## INIT              (Step 4 reg dump + Step 6)
- Ordered SCU / A-Bus / VDP setup the game assumes before ENTRY: ...

## IO_MAP            (Step 6)
| address | dir | value game needs | meaning |
|---------|-----|------------------|---------|
| 0x00400001 | RD | 0x.. | dipsw / region |
| ... | | | |

## EEPROM            (Step 6 + stvbios.nv)
- 93C46 access pattern: ...
- Bytes game reads back: ...
```

- [ ] **Step 8: Self-check the spec is complete and commit**

Run (in repo):
```bash
cd /c/Users/mixio/Documents/GitHub/SAROO-STV
grep -nE '0x\.\.\.|TODO|TBD|\bblank\b' docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md && echo "INCOMPLETE — fill remaining" || echo "complete"
```
Expected: `complete` (no unfilled `0x....`/TODO). Then commit:
```bash
git add docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md
git commit -m "docs(recon): bakubaku bridge spec from MAME stv reference"
```

---

## Task 2: M1 — Vanilla Yabause SDL baseline in WSL2

**Files:**
- Create (WSL): clone at `~/yabause-stv/` ; built binary `~/yabause-stv/src/sdl/yabause` (path confirmed in Step 3)
- Create (WSL): `~/yabause-stv/bios/saturn-jp-v100.bin` (extracted Saturn BIOS)

**Interfaces:**
- Produces (consumed by the M2–M5 plan): a building, runnable vanilla Yabause SDL binary in WSL2 whose source tree is the fork the bridge module will be added to; confirmation that the JP Saturn BIOS loads and the core renders under WSLg.

- [ ] **Step 1: Confirm WSLg display works**

Run (WSL):
```bash
echo $DISPLAY ; sudo apt-get install -y x11-apps >/dev/null 2>&1 ; (xeyes & sleep 3 ; kill %1) 2>/dev/null
```
Expected: `$DISPLAY` is non-empty (e.g. `:0`) and an `xeyes` window briefly appears on the Windows desktop. If nothing shows, WSLg is the blocker — resolve before continuing (Win11 WSLg should be on by default; `wsl --update` from PowerShell if not).

- [ ] **Step 2: Install Yabause SDL build dependencies**

Run (WSL):
```bash
sudo apt-get update
sudo apt-get install -y git cmake build-essential libsdl2-dev libgl1-mesa-dev \
    libglu1-mesa-dev freeglut3-dev libboost-all-dev zlib1g-dev
```
Expected: all install without error.

- [ ] **Step 3: Clone vanilla Yabause and build the SDL port**

Run (WSL):
```bash
cd ~ && git clone https://github.com/Yabause/yabause.git yabause-stv
cd ~/yabause-stv && mkdir -p build && cd build
cmake .. -DYAB_PORTS=sdl -DCMAKE_BUILD_TYPE=Debug
make -j"$(nproc)" 2>&1 | tail -20
find ~/yabause-stv -name yabause -type f -perm -u+x
```
Expected: `make` completes and a `yabause` executable path prints. If the build breaks on Ubuntu 22.04 (known bitrot risk), record the exact error in `~/yabause-stv/BUILD_NOTES.txt`; if unfixable within ~30 min, this is the documented trigger to escalate to Kronos (separate decision — stop and report).

- [ ] **Step 4: Stage the JP Saturn BIOS**

Run (WSL):
```bash
cd ~/yabause-stv && mkdir -p bios
unzip -o "/mnt/c/Users/mixio/Downloads/Sega Saturn BIOS v1.00 (1994)(Sega)(JP)(M6).zip" -d /tmp/sbios
cp "/tmp/sbios/Sega Saturn BIOS v1.00 (1994)(Sega)(JP)(M6).bin" bios/saturn-jp-v100.bin
ls -l bios/saturn-jp-v100.bin   # expect 524288 bytes
```
Expected: `bios/saturn-jp-v100.bin`, exactly 524288 bytes.

- [ ] **Step 5: Boot the Saturn BIOS (no disc) and confirm the core renders**

Run (WSL — adjust the binary path from Step 3):
```bash
cd ~/yabause-stv
BIN=$(find . -name yabause -type f -perm -u+x | head -1)
"$BIN" -b bios/saturn-jp-v100.bin -r 4 &   # region 4 = Japan; no -i disc
sleep 12 ; import -window root /tmp/yab_bios.png 2>/dev/null || true
```
Expected: a Yabause window opens under WSLg and shows the Saturn power-on / CD-player ("no disc") screen — i.e. BIOS executes and VDP2 renders. This is the baseline: real Saturn BIOS + Yabause core + WSLg display all working. Screenshot saved for the record.

- [ ] **Step 6: Record baseline notes (no commit needed — separate repo)**

Write `~/yabause-stv/BUILD_NOTES.txt` capturing: the confirmed `yabause` binary path, the working launch command, the BIOS path/size, and any build patches applied. (This tree is a separate Yabause clone, not the SAROO-STV repo; the M2–M5 plan will turn it into a git fork and add the `stv_bridge` module.)

---

## Self-Review

**Spec coverage (against the design spec M0/M1):**
- ✅ IC→address map → Task 1 Step 5
- ✅ Real entry point / exec-header unknown → Task 1 Step 4 (empirical via MAME debugger)
- ✅ 315-5649 I/O map + values → Task 1 Step 6
- ✅ 93C46 EEPROM behavior → Task 1 Step 6 (+ stvbios.nv)
- ✅ Dumps-good sanity + correct-picture reference → Task 1 Step 3
- ✅ Vanilla Yabause SDL build in WSL2 → Task 2 Steps 2–3
- ✅ JP Saturn BIOS loads, core renders under WSLg → Task 2 Steps 4–5
- ✅ Kronos escalation trigger documented → Task 2 Step 3

**Placeholder scan:** The `0x....` tokens appear only inside the *template* the recon task fills (Task 1 Step 7) and the self-check that rejects them (Step 8) — they are the deliverable's blanks, not plan blanks. No "TODO/handle appropriately/similar to" instructions to an implementer.

**Type consistency:** The five spec section names (`IC_MAP`, `ENTRY`, `INIT`, `IO_MAP`, `EEPROM`) are identical in the Interfaces block, the doc template (Step 7), and the self-check (Step 8).

**Out of scope (deferred to the M2–M5 plan):** cart mapper, header overlay, ST-V init stub, I/O shim, EEPROM shim, input — all require Task 1's output as input and are intentionally not in this plan.
