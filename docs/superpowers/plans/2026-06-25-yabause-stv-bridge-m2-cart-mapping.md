# Yabause ST-V Bridge — M2 Cart Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `CART_STV` cartridge type to the vanilla Yabause fork that loads the `bakubaku` ST-V ROM set into the Saturn A-Bus CS0 region (`0x02000000`–`0x03FFFFFF`) exactly as MAME's `stv` driver lays it out, so the SH-2 reads the correct bytes at every A-Bus address. This is the software equivalent of SAROO's FPGA CS0 mapping. Verification: the SH-2-visible A-Bus read at `0x02200000` returns `"SEGA ST-V(TITAN)"`, and a word-swapped data ROM read matches the source file.

**Architecture:** Yabause dispatches all CS0 reads/writes (`0x02000000`–`0x03FFFFFF`, memory.c pages `0x200`–`0x3FF`) through `CartridgeArea->Cs0Read*/Write*` function pointers (set in `CartInit`, cs0.c:1027). We add `case CART_STV` to `CartInit` that allocates a 32 MB `rom` buffer, loads the five pre-extracted IC files into it at the offsets the M0 recon documented, and installs `StvCs0Read{Byte,Word,Long}` handlers that read from the buffer. No header overlay or boot handoff yet — that is M3.

**Tech Stack:** C (Yabause core), `T1MemoryInit`/`T1ReadByte/Word/Long` big-endian buffer helpers; built GTK port in WSL2 (`/root/yabause-stv/build/src/gtk/yabause`); software renderer only.

## Global Constraints

- Yabause fork tree: `/root/yabause-stv/yabause/src/` (WSL). Build dir: `/root/yabause-stv/build`. Binary: `build/src/gtk/yabause`.
- Run all Linux commands from Git Bash via `wsl.exe bash -lc "…"`.
- Software renderer only at runtime (`VideoCore=2`); OGL segfaults under WSLg/Mesa.
- CS0 region = `0x02000000`–`0x03FFFFFF` (32 MB). A-Bus address = `0x02000000` + cart-region offset (MAME copies its `cart` region 1:1 into the A-Bus window).
- bakubaku IC→cart-offset map (from `docs/superpowers/recon/2026-06-25-bakubaku-bridge-spec.md`, section IC_MAP), all verbatim:
  - `fpr17969.13` (1 MB): ROM_LOAD16_BYTE odd bytes at cart offset `0x0000001` (file byte i → buf[1+2i]); plain reload at `0x0200000`; plain reload at `0x0300000`.
  - `mpr17970.2` (4 MB): WORD_SWAP at `0x0400000`.
  - `mpr17971.3` (4 MB): WORD_SWAP at `0x0800000`.
  - `mpr17972.4` (4 MB): WORD_SWAP at `0x0C00000`.
  - `mpr17973.5` (4 MB): WORD_SWAP at `0x1000000`.
  - WORD_SWAP = within each 16-bit word, swap the two bytes (buf[off+2i]=file[2i+1], buf[off+2i+1]=file[2i]).
- ROM source: pre-extract `bakubaku.zip` to `/root/yabause-stv/stvroms/bakubaku/` (the 5 IC files).
- Do NOT add a header overlay, trampoline, IOGA, or EEPROM logic in this plan — out of scope (M3/M4).

---

## Task 1: STV cart type scaffolding + selection

**Files:**
- Modify: `/root/yabause-stv/yabause/src/cs0.h` (add `CART_STV` define + handler prototypes)
- Modify: `/root/yabause-stv/yabause/src/cs0.c` (add `case CART_STV` in `CartInit`, stub handlers)

**Interfaces:**
- Produces: `#define CART_STV 12`; a `case CART_STV` branch in `CartInit(const char *filename, int type)` that allocates `CartridgeArea->rom` via `T1MemoryInit(0x2000000)` and installs `StvCs0ReadByte/Word/Long` + `DummyCs0Write*` (CS0 is read-only). The `filename` passed is the directory `/root/yabause-stv/stvroms/bakubaku/`.

- [ ] **Step 1: Add the cart type and prototypes to cs0.h**

After the existing `#define CART_USBDEV 11` line, add:
```c
#define CART_STV               12
```
This is the new ST-V bridge cart type. No prototype changes needed in the header (handlers are file-static in cs0.c).

- [ ] **Step 2: Add static STV read handlers (buffer reads) to cs0.c**

Before `int CartInit(...)` (around cs0.c:1010, after the ROM16MBIT handlers), add:
```c
//////////////////////////////////////////////////////////////////////////////
// STV bridge cart (SAROO software twin) — CS0 = ST-V ROM, read-only
//////////////////////////////////////////////////////////////////////////////

static u8 FASTCALL StvCs0ReadByte(UNUSED SH2_struct *sh, u32 addr)
{
   return T1ReadByte(CartridgeArea->rom, addr & 0x01FFFFFF);
}

static u16 FASTCALL StvCs0ReadWord(UNUSED SH2_struct *sh, u32 addr)
{
   return T1ReadWord(CartridgeArea->rom, addr & 0x01FFFFFF);
}

static u32 FASTCALL StvCs0ReadLong(UNUSED SH2_struct *sh, u32 addr)
{
   return T1ReadLong(CartridgeArea->rom, addr & 0x01FFFFFF);
}
```
(`0x01FFFFFF` masks the 32 MB CS0 window into the 32 MB buffer. Writes use the existing `DummyCs0Write*` — CS0 ROM is read-only.)

- [ ] **Step 3: Add the CART_STV case to CartInit**

Inside the `switch(type)` in `CartInit` (cs0.c:1027), after the `CART_PAR` case block, add:
```c
      case CART_STV: // ST-V ROM bridge (bakubaku) — see stv_bridge recon spec
      {
         if ((CartridgeArea->rom = T1MemoryInit(0x2000000)) == NULL) // 32 MB CS0
            return -1;

         if (StvLoadRoms((const char *)filename) != 0) // load ICs into ->rom
            return -1;

         CartridgeArea->Cs0ReadByte = &StvCs0ReadByte;
         CartridgeArea->Cs0ReadWord = &StvCs0ReadWord;
         CartridgeArea->Cs0ReadLong = &StvCs0ReadLong;
         // writes stay Dummy (CS0 ROM is read-only)
         break;
      }
```
`StvLoadRoms` is implemented in Task 2; declare it `static int StvLoadRoms(const char *dir);` near the top of cs0.c so this compiles.

- [ ] **Step 4: Add a temporary StvLoadRoms stub so the file compiles**

Near the top of cs0.c (after includes), add a forward decl, and just before `CartInit` add a stub:
```c
static int StvLoadRoms(const char *dir)
{
   (void)dir;
   return 0; // stub — Task 2 fills this in
}
```

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
wsl.exe bash -lc 'cd /root/yabause-stv/build && make -j"$(nproc)" 2>&1 | tail -8'
```
Expected: build succeeds, no errors referencing cs0.c.

- [ ] **Step 6: Commit**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv && git add yabause/src/cs0.c yabause/src/cs0.h && git commit -m "feat(stv): CART_STV cart type scaffolding + read handlers"'
```
(First `git` use in this tree may need `git init` + initial commit of the pristine clone — if `git status` errors, run `cd /root/yabause-stv && git init && git add -A && git commit -m "vanilla yabause v0.9.15 baseline"` first, then the commit above.)

---

## Task 2: Load bakubaku IC files into the CS0 buffer

**Files:**
- Modify: `/root/yabause-stv/yabause/src/cs0.c` (implement `StvLoadRoms`)

**Interfaces:**
- Consumes: `CartridgeArea->rom` (32 MB `T1MemoryInit` buffer) allocated in Task 1's `CART_STV` case.
- Produces: `static int StvLoadRoms(const char *dir)` — fills `->rom` from the 5 IC files in `dir` per the IC_MAP. Returns 0 on success, -1 on any file error.

- [ ] **Step 1: Pre-extract the ROM set**

```bash
wsl.exe bash -lc 'mkdir -p /root/yabause-stv/stvroms/bakubaku && \
  unzip -o /mnt/c/Users/mixio/Downloads/bakubaku.zip -d /root/yabause-stv/stvroms/bakubaku && \
  ls -l /root/yabause-stv/stvroms/bakubaku'
```
Expected: `fpr17969.13` (1048576), `mpr17970.2`/`mpr17971.3`/`mpr17972.4`/`mpr17973.5` (4194304 each).

- [ ] **Step 2: Write a host self-test for the load logic**

Create `/root/yabause-stv/yabause/src/test_stvload.c`:
```c
/* Host test for STV ROM load layout. Compile standalone; no Yabause deps. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char buf[0x2000000];

/* mirror of StvLoadRoms logic, operating on the global buf */
static int load_plain(const char *path, unsigned off, unsigned len){
   FILE*f=fopen(path,"rb"); if(!f){perror(path);return -1;}
   size_t n=fread(buf+off,1,len,f); fclose(f); return n==len?0:-1; }
static int load_word_swap(const char *path, unsigned off, unsigned len){
   FILE*f=fopen(path,"rb"); if(!f){perror(path);return -1;}
   unsigned char*t=malloc(len); size_t n=fread(t,1,len,f); fclose(f);
   if(n!=len){free(t);return -1;}
   for(unsigned i=0;i+1<len;i+=2){buf[off+i]=t[i+1];buf[off+i+1]=t[i];}
   free(t); return 0; }
static int load_byte_odd(const char *path, unsigned off, unsigned len){
   FILE*f=fopen(path,"rb"); if(!f){perror(path);return -1;}
   unsigned char*t=malloc(len); size_t n=fread(t,1,len,f); fclose(f);
   if(n!=len){free(t);return -1;}
   for(unsigned i=0;i<len;i++) buf[off+1+2*i]=t[i];
   free(t); return 0; }

int main(int argc,char**argv){
   const char*d=argc>1?argv[1]:"/root/yabause-stv/stvroms/bakubaku";
   char p[512];
   #define IC(n) (snprintf(p,sizeof p,"%s/%s",d,n),p)
   if(load_byte_odd(IC("fpr17969.13"),0x0000000,0x100000)) return 2;
   if(load_plain   (IC("fpr17969.13"),0x0200000,0x100000)) return 2;
   if(load_plain   (IC("fpr17969.13"),0x0300000,0x100000)) return 2;
   if(load_word_swap(IC("mpr17970.2"),0x0400000,0x400000)) return 2;
   if(load_word_swap(IC("mpr17971.3"),0x0800000,0x400000)) return 2;
   if(load_word_swap(IC("mpr17972.4"),0x0C00000,0x400000)) return 2;
   if(load_word_swap(IC("mpr17973.5"),0x1000000,0x400000)) return 2;

   /* Check A: plain mirror at 0x200000 reads "SEGA ST-V(TITAN)" */
   if(memcmp(buf+0x200000,"SEGA ST-V(TITAN)",16)!=0){
      printf("FAIL: 0x02200000 != SEGA ST-V(TITAN), got '%.16s'\n",buf+0x200000); return 1; }
   /* Check B: word-swapped mpr first word — read source word 0, swap, compare */
   { FILE*f=fopen(IC("mpr17970.2"),"rb"); unsigned char s[2]; fread(s,1,2,f); fclose(f);
     if(buf[0x400000]!=s[1] || buf[0x400001]!=s[0]){
        printf("FAIL: word-swap at 0x02400000 wrong\n"); return 1; } }
   printf("PASS: STV ROM layout (SEGA magic @0x200000, word-swap @0x400000)\n");
   return 0;
}
```

- [ ] **Step 3: Run the host test to verify it FAILS first (logic not wired)**

Build and run:
```bash
wsl.exe bash -lc 'cd /root/yabause-stv/yabause/src && gcc -O0 -o /tmp/test_stvload test_stvload.c && /tmp/test_stvload'
```
Expected: `PASS` — this test embeds the load logic directly, so it should pass immediately and confirms the OFFSETS/TRANSFORMS are correct against the real files. (If it FAILs, the IC_MAP transform is wrong — fix here before touching cs0.c. This test is the source of truth for the transform.)

- [ ] **Step 4: Implement StvLoadRoms in cs0.c using the verified logic**

Replace the Task 1 stub `StvLoadRoms` with:
```c
static int StvLoadFile(const char *dir, const char *name, u32 off, u32 len, int mode)
{
   /* mode: 0=plain, 1=word-swap, 2=byte-odd */
   char path[512];
   snprintf(path, sizeof(path), "%s/%s", dir, name);
   FILE *f = fopen(path, "rb");
   if (!f) return -1;
   u8 *tmp = (u8 *)malloc(len);
   if (!tmp) { fclose(f); return -1; }
   size_t n = fread(tmp, 1, len, f);
   fclose(f);
   if (n != len) { free(tmp); return -1; }
   u8 *rom = (u8 *)CartridgeArea->rom;
   if (mode == 0)                              // plain
      memcpy(rom + off, tmp, len);
   else if (mode == 1)                         // word-swap
      for (u32 i = 0; i + 1 < len; i += 2) { rom[off+i] = tmp[i+1]; rom[off+i+1] = tmp[i]; }
   else                                        // byte-odd (offset+1, stride 2)
      for (u32 i = 0; i < len; i++) rom[off + 1 + 2*i] = tmp[i];
   free(tmp);
   return 0;
}

static int StvLoadRoms(const char *dir)
{
   if (StvLoadFile(dir, "fpr17969.13", 0x0000000, 0x100000, 2)) return -1;
   if (StvLoadFile(dir, "fpr17969.13", 0x0200000, 0x100000, 0)) return -1;
   if (StvLoadFile(dir, "fpr17969.13", 0x0300000, 0x100000, 0)) return -1;
   if (StvLoadFile(dir, "mpr17970.2",  0x0400000, 0x400000, 1)) return -1;
   if (StvLoadFile(dir, "mpr17971.3",  0x0800000, 0x400000, 1)) return -1;
   if (StvLoadFile(dir, "mpr17972.4",  0x0C00000, 0x400000, 1)) return -1;
   if (StvLoadFile(dir, "mpr17973.5",  0x1000000, 0x400000, 1)) return -1;
   return 0;
}
```
Ensure `<stdio.h>`, `<stdlib.h>`, `<string.h>` are included in cs0.c (they typically are; add if the build complains).

- [ ] **Step 5: Add a one-shot runtime self-check behind an env var**

So we can verify the live emulator path without a debugger, add to the end of the `CART_STV` case (after handlers are set), guarded so it only prints:
```c
         if (getenv("STV_SELFTEST")) {
            u32 hi = StvCs0ReadLong(NULL, 0x02200000);
            u32 lo = StvCs0ReadLong(NULL, 0x02200004);
            fprintf(stderr, "[STV] CS0@0x02200000 = %08X %08X (expect 53454741 2053542D)\n", hi, lo);
         }
```
`53454741 2053542D` = "SEGA ST-" big-endian, proving the live `StvCs0ReadLong` path returns the header.

- [ ] **Step 6: Build and run the live self-check**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv/build && make -j"$(nproc)" 2>&1 | tail -5'
```
The cart type is selected via Yabause config (`CartType=12`) or however the GTK port exposes it. Simplest for the check: temporarily hardcode the M3 entry by running with `STV_SELFTEST=1` and a config that sets `CartType=12` and `CartPath=/root/yabause-stv/stvroms/bakubaku`. If wiring the GTK config menu is non-trivial, set the cart in `~/.yabause/yabause.cfg` (`CartType=12`). Then:
```bash
wsl.exe bash -lc 'cd /root/yabause-stv; BIN=build/src/gtk/yabause; \
  STV_SELFTEST=1 timeout 8 "$BIN" -b bios/saturn-jp-v100.bin -r 4 2>&1 | grep "\[STV\]"'
```
Expected: `[STV] CS0@0x02200000 = 53454741 2053542D (expect 53454741 2053542D)`.

- [ ] **Step 7: Commit**

```bash
wsl.exe bash -lc 'cd /root/yabause-stv && git add yabause/src/cs0.c yabause/src/test_stvload.c && git commit -m "feat(stv): load bakubaku ICs into CS0 per M0 IC_MAP; host + live self-test"'
```

---

## Self-Review

**Spec coverage (against design spec M2 + recon IC_MAP):**
- ✅ New cart type mapping ST-V ROM into CS0 → Task 1
- ✅ bakubaku ICs loaded at M0-documented offsets/transforms → Task 2
- ✅ SH-2-visible A-Bus reads correct bytes (SEGA magic @0x02200000) → Task 2 Steps 3 & 6
- ✅ Read-only CS0 (writes Dummy) → Task 1 Step 3
- ✅ Software-renderer constraint respected (no rendering added) → n/a, no video code touched

**Placeholder scan:** Task 1 Step 4 deliberately adds a stub that Task 2 Step 4 replaces — the plan states this explicitly; not a hidden placeholder. All code blocks are complete.

**Type consistency:** `StvLoadRoms(const char *dir)` declared (Task 1 Step 3) and defined (Task 2 Step 4) with the same signature; `StvCs0ReadByte/Word/Long` names identical in handler defs (Task 1 Step 2) and CartInit assignment (Task 1 Step 3) and self-check (Task 2 Step 5).

**Out of scope (subsequent plans):**
- **M3 — boot handoff** (OPEN RESEARCH): how a stock Saturn BIOS transfers control into the cart. Real Saturn cart-boot (Action Replay-style) vs. a trampoline that the BIOS jumps to vs. directly seeding SH-2 PC + copying IP (per M0: fpr plain @0x02200000 → HWRAM 0x06000000, jump 0x060249FE). Needs a Yabause-boot-path recon before planning.
- **M4 — IOGA shim** (memory.c page 0x004 @0x00400000, per M0 IO_MAP) + **93C46 EEPROM shim** (smpc.c PDR1/PDR2, per M0 EEPROM).
- **M5 — input** (keyboard → JAMMA coin/start/dirs).
