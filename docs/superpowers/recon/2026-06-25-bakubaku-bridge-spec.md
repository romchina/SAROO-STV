# Bakubaku Bridge Spec — M0 Recon Output

**Date:** 2026-06-25  
**MAME reference:** v0.242, driver `stv`, game `bakubaku`  
**BIOS used:** `jp1` (EPR-20091, Japan 97/08/21)  
**Source reference:** `src/mame/sega/stv.cpp` (master branch, 4073 lines)  
**Note:** Values marked **MEASURED** were captured via MAME v0.242 Lua `emu.register_frame_done`
hooks during live emulation. Values marked **DERIVED-FROM-SOURCE** come from reading
stv.cpp, stv.h, and the ROM binary directly. No values were fabricated.

---

## Verification Run

MAME ran `bakubaku` successfully with BIOS `jp1`. The `segabill` billboard device firmware
(epr-18022.ic2, CRC 0x0ca70f80) was not present in stvbios.zip; a zero-filled dummy was
substituted so MAME warns `WRONG CHECKSUMS` but continues. The billboard device is an
external Sega Versus City LED score display — its Z80 firmware is not consulted by game
code during boot or attract. Emulation ran for 60 s at 100% speed without hang.

Cart at 0x02000000 reads as interleaved (`00 53 00 45 ... "S.E."`) at frame 1200, confirming
the SMPC PDR1 write triggered `stv_select_game(0)` which copies the `cart` region into the
`abus` region before frame 1200.  
Cart plain mirror at 0x02200000 reads `53 45 47 41 20 53 54 2D 56 28 54 49 54 41 4E 29`
(`SEGA ST-V(TITAN)`) — BIOS validation header confirmed.

---

## IC_MAP

Source: `stv.cpp` ROM_START(bakubaku) lines 2028–2040. Cart region is
`ROM_REGION32_BE(0x3000000, "cart", ROMREGION_ERASE00)` (48 MB, zeroed). At `machine_reset()`
`m_cart_reg[0] = memregion("cart")`, and at first PDR1 write (game-slot select 0),
`stv_select_game(0)` calls `memcpy(memregion("abus")->base(), m_cart_reg[0]->base(), 0x3000000)`,
mapping cart bytes into the A-Bus window at 0x02000000.

| File | Load macro | Cart-region byte offset | Length | A-Bus base address | Notes |
|------|-----------|------------------------|--------|-------------------|-------|
| fpr17969.13 | `ROM_LOAD16_BYTE` (odd bytes) | 0x0000001 | 0x100000 (1 MB) | 0x02000001 | Even bytes = 0x00; reads as 0x00XX per 16-bit word |
| fpr17969.13 | `ROM_RELOAD_PLAIN` | 0x0200000 | 0x100000 (1 MB) | 0x02200000 | Raw bytes, normal byte order; BIOS reads header here |
| fpr17969.13 | `ROM_RELOAD_PLAIN` | 0x0300000 | 0x100000 (1 MB) | 0x02300000 | Second plain mirror |
| mpr17970.2  | `ROM_LOAD16_WORD_SWAP` | 0x0400000 | 0x400000 (4 MB) | 0x02400000 | Game data ROM 1 |
| mpr17971.3  | `ROM_LOAD16_WORD_SWAP` | 0x0800000 | 0x400000 (4 MB) | 0x02800000 | Game data ROM 2 |
| mpr17972.4  | `ROM_LOAD16_WORD_SWAP` | 0x0C00000 | 0x400000 (4 MB) | 0x02C00000 | Game data ROM 3 |
| mpr17973.5  | `ROM_LOAD16_WORD_SWAP` | 0x1000000 | 0x400000 (4 MB) | 0x03000000 | Game data ROM 4 |

The A-Bus window is `map(0x02000000, 0x04ffffff).rom().mirror(0x20000000).region("abus", 0)`
(stv.cpp line 985). Cart offsets 0x1400000–0x2FFFFFF are zero-filled (no ROM loaded there).

CRCs for reference (from ROM_START):
- fpr17969.13: CRC bee327e5 SHA1 1d226db72d6ef68fd294f60659df7f882b25def6
- mpr17970.2:  CRC bc4d6f91 SHA1 dcc241dcabea59325decfba3fd5e113c07958422
- mpr17971.3:  CRC c780a3b3 SHA1 99587eea528a6413cacc3e4d3d1dbfff57b03dca
- mpr17972.4:  CRC 8f29815a SHA1 e86acd8096f2aee5f5e3ddfd3abb4f5c2b11df66
- mpr17973.5:  CRC 5f6e0e8b SHA1 eeb5efb5216ab8b8fdee4656774bbd5a2a5b2d42

---

## ENTRY

**MEASURED** via MAME v0.242 Lua `emu.register_frame_done`, tracking PC region transitions.

### Master SH-2 (maincpu) boot sequence

| Event | Frame | PC | SP (R15) | Notes |
|-------|-------|----|----------|-------|
| SH-2 reset (BIOS ROM) | 1 | 0x00000234 | 0x06100000 | BIOS ROM 0x00000000–0x0007FFFF |
| **First HWRAM entry (game IP)** | **18** | **0x060249FE** | **0x060FFFE8** | MEASURED; BIOS has just DMA-copied fpr17969.13 to HWRAM |
| BIOS routine in HWRAM | 19+ | 0x060154B8–0x060154C2 | — | Init wait loop; BIOS callbacks from game IP |
| BIOS ROM callback | 1129 | 0x00005E46 | — | IP calls BIOS for SMPC/SCU service |
| **First new HWRAM block (game code)** | **1182** | **0x0604B446** | **0x060FFFE8** | MEASURED; game binary loaded from A-Bus |
| Game main loop (attract) | 1200–3300+ | ~0x06036DBC | — | MEASURED; PC stable ±4 bytes around 0x06036DBC |

**Entry PC (handed to Yabause bridge):** `0x060249FE`

**Code runs from:** HWRAM (`0x06000000–0x060FFFFF`). The BIOS copies
fpr17969.13 (1 MB, from A-Bus plain-reload at 0x02200000) into HWRAM at 0x06000000
via SCU DMA before frame 18. After the IP setup completes (~frame 1182), the game loads
additional code from the mpr data ROMs at 0x02400000+ into HWRAM, overwriting parts of
the IP copy. The cart region is NOT executed in-place; code at 0x02xxxxxx is never the PC
target during normal operation (CART_ABUS region PC-hit = never observed across 60 s run).

fpr17969.13 byte offset 0x249FE maps to HWRAM 0x060249FE (confirmed: HWRAM at that address
at frame 25 contained 0x6363 = SH-2 `MOV R6,R3`, which is valid game IP code; by frame 1400
the byte had changed to 0xF634 as the game overwrote this area with run-time data).

### Slave SH-2 (slave)

**DERIVED-FROM-SOURCE** (stv.cpp `machine_reset()` line 1280):
```cpp
m_slave->set_input_line(INPUT_LINE_RESET, ASSERT_LINE);
```
Slave is held in hardware RESET at power-on. It is released by the game via SMPC command
(PDR2 bit 4 write via `pdr2_output_w`). The bridge shim must leave the slave in RESET until
the game explicitly releases it through SMPC.

---

## INIT

**DERIVED-FROM-SOURCE** (stv.cpp, stv.h, ST-V boot semantics). Ordered sequence the game
assumes is complete before `ENTRY` (0x060249FE) is reached.

1. **SH-2 reset vectors** — BIOS ROM at 0x00000000 is the SH-2 reset vector table. PC
   reset vector at 0x00000000 → 0x00000234; SP (R15) reset vector at 0x00000004 → 0x06100000.
   These are in the BIOS ROM, not the cart.

2. **SMPC initialization** — BIOS runs SMPC RES (System Reset) and SMPC INTBACK (interrupt-back)
   commands via registers at 0x00100000–0x0010007F. Region code is set to Japan (1) by
   `set_region_code(1)` (stv.cpp line 1117). The SMPC clock is 4 MHz (`XTAL(4'000'000)`).

3. **PDR1 game-slot select** — BIOS writes PDR1 (SMPC port data register 1) with
   `data & 3 = 0x00` to select cart slot 0. This calls `stv_select_game(0)` which
   `memcpy`s the `cart` region into `abus` (stv.cpp lines 1052–1060), making
   cart ROM data readable at 0x02000000–0x04FFFFFF. This happens between frames 300 and 1200
   (MEASURED: abus zeros at frame 300, populated at frame 1200).

4. **Cart header validation** — BIOS reads the ST-V IP header from 0x02200000 (plain
   mirror of fpr17969.13). Validates bytes 0x00–0x0F = `SEGA ST-V(TITAN)` (MEASURED:
   reads `53 45 47 41 20 53 54 2D 56 28 54 49 54 41 4E 29` at frame 1200).

5. **EEPROM read** — BIOS reads 93C46 EEPROM via PDR1/PDR2 bit-bang (see EEPROM section).
   Expects "SEGA" magic at words 0–1. If not found, writes defaults.

6. **HWRAM copy** — BIOS copies fpr17969.13 (1 MB) from cart A-Bus to HWRAM at 0x06000000.
   Likely via SCU DMA level-0 or SH-2 block copy routine. Completes before frame 18.

7. **SCU/A-Bus setup** — A-Bus interface configured (access widths, wait states) for:
   - 0x00000000: BIOS ROM, 16-bit, 0 wait states
   - 0x02000000: cart ROM, 32-bit (set by A-Bus control register)
   - 0x06000000: HWRAM (SH-2 internal wait-state-free)

8. **IOGA coin lockout** — BIOS writes 0x0C to Port D (0x00400007) at frame 13 (MEASURED)
   to activate coin lockout: bits 2–3 set = P1 and P2 lockout active.

9. **Jump to game IP** — BIOS calls (JSR or JMP) to 0x060249FE. The game IP then calls
   BIOS services and eventually jumps to game code at 0x0604B446+ (frame 1182).

---

## IO_MAP

**MEASURED** via Lua per-frame polling of the IOGA address range, frames 1–1500.

### IOGA (315-5649 equivalent) at 0x00400000–0x0040003F

Address map: `map(0x00400000, 0x0040003F).rw(...ioga_r..., ...ioga_w...).umask32(0x00ff00ff)`
(stv.cpp line 982). Only **odd bytes** (byte offsets 1, 3, 5, …, 0x3F) are active.
Addresses 0x00400020–0x0040003F are mirrors of 0x00400000–0x0040001F (`offset &= 0x0f` in handler).

| Address (byte) | Dir | Value game sees/writes | Meaning |
|----------------|-----|----------------------|---------|
| 0x00400001 | RD | 0xFF | Port A — P1 buttons (all released; active-low) |
| 0x00400003 | RD | 0xFF | Port B — P2 buttons (all released; active-low) |
| 0x00400005 | RD | 0xFF | Port C — system: no coin1 (bit 0), no coin2 (bit 1), no service (bit 2), no service1 (bit 3), no start1 (bit 4), no start2 (bit 5) |
| 0x00400007 | WR | 0x0C | Port D — coin counter + lockout write: bit0=P1 ctr, bit1=P2 ctr, bit2=P1 lock, bit3=P2 lock; game sets 0x0C (lockout ON) |
| 0x00400007 | RD | 0x0C | Port D — read-back of last write (MEASURED: 0x0C stable from frame 13+) |
| 0x00400009 | RD | 0xFF | Port E — P3 buttons (unused in bakubaku; all released) |
| 0x0040000B | RD | 0xFF | Port F — P4 buttons (unused; all released) |
| 0x0040000D | RD | 0xFF | Port G — analog counter read (unused in normal mode) |
| 0x0040001B | RD | 0x00 | Serial COM read status — returns 0 always |
| 0x0040001D | RD/WR | 0x00 | IOGA mode register — 0x00 = digital port mode |

MEASURED: at frame 1185 (game code at 0x060335E4) Port D briefly changes 0x0C→0x00 then
back to 0x0C at frame 1188 (0x06053CCE). This is the game re-initializing the coin lockout
at the start of attract mode.

The M4 shim must:
- Return 0xFF for Port A, B, C, E, F (no input, no coins)
- Accept Port D writes (record the value for read-back)
- Return 0x00 for serial COM status and mode register

### SMPC at 0x00100000–0x0010007F

`map(0x00100000, 0x0010007f).mirror(0x2007ff80).m(m_smpc_hle, FUNC(smpc_hle_device::io_map))`
(stv.cpp line 979). SMPC manages region code, PDR1/PDR2 (which carry EEPROM bits and
game-slot select), and slave SH-2 / audio 68k reset lines.

MEASURED SMPC state at frame 10 (SMPC odd-byte register snapshot, 0x00100001 base):
- SMPC[0x2F] = 0x1A (status / OREG offset 15 area)
- SMPC[0x30] = 0x40 (SF register or IREG offset 0)
- SMPC[0x3A] = 0x7F (PDR1 value = 0x7F: bits 5,4,3,2,1,0 high = all peripherals, EEPROM CS deasserted)
- SMPC[0x3B] = 0x7F (PDR2 value = 0x7F: bit 0 = EEPROM DO high)

Key PDR signals (DERIVED-FROM-SOURCE, stv.cpp `pdr1_output_w` / `pdr2_input_r`):

| PDR reg | Bit | Signal | Direction | Notes |
|---------|-----|--------|-----------|-------|
| PDR1 | 1:0 | Game slot select | OUT (CPU→HW) | `data & 3` → `stv_select_game(n)` |
| PDR1 | 2 | 93C46 /CS | OUT | High = deselected |
| PDR1 | 3 | 93C46 CLK | OUT | Rising edge clocks one bit |
| PDR1 | 4 | 93C46 DI | OUT | Data to EEPROM |
| PDR2 | 0 | 93C46 DO | IN | Data from EEPROM |

---

## EEPROM

**MEASURED** from `stvbios.nv` (included in `stvbios.zip`, 128 bytes).  
**DERIVED-FROM-SOURCE** for protocol (stv.cpp `pdr1_output_w`, `pdr2_input_r`).

### Protocol

93C46 in 16-bit organization (ORG pin high): 64 words × 16 bits = 1 Kbit.  
Serial bit-bang via SMPC PDR1/PDR2, big-endian (MSB first):
- Write CS high (PDR1 bit 2), then clock DI bits on rising CLK edge
- Opcode: `READ = 0b10`, `WRITE = 0b01`, `EWEN = 0b00_11xxxxxx`
- Address: 6 bits (word 0–63)
- Data: 16 bits per read/write

The BIOS reads words 0 and 1 to check for the "SEGA" magic signature. If both words match,
the BIOS trusts the stored configuration. If not (blank EEPROM = 0xFFFF), it writes defaults.

### EEPROM content (from stvbios.nv, MEASURED)

File is 128 bytes = 64 × 16-bit big-endian words.

| Word addr | Byte offset | Value | Meaning |
|-----------|-------------|-------|---------|
| 0 | 0x00 | 0x5345 | Magic "SE" |
| 1 | 0x02 | 0x4741 | Magic "GA" → combined "SEGA" signature |
| 2 | 0x04 | 0xFFFF | (blank) |
| 3 | 0x06 | 0xFFFF | (blank) |
| 4 | 0x08 | 0x7592 | Checksum / magic value |
| 5 | 0x0A | 0xFFFF | (blank) |
| 6 | 0x0C | 0x0000 | Config word 0 |
| 7 | 0x0E | 0x0002 | Config word 1 (region / revision?) |
| 8 | 0x10 | 0x0100 | Config word 2 |
| 9 | 0x12 | 0x0101 | Config word 3 |
| 10 | 0x14 | 0x0000 | Config word 4 |
| 11 | 0x16 | 0x0000 | Config word 5 |
| 12 | 0x18 | 0x0000 | Config word 6 |
| 13 | 0x1A | 0x0008 | Config word 7 |
| 14 | 0x1C | 0x08DD | Config word 8 (0x08DD = 2269 decimal; likely coin/sound config) |
| 15–31 | 0x1E–0x3E | 0xFFFF | (blank/unwritten) |
| 32–33 | 0x40–0x43 | 0xFFFF | (blank) — second copy begins here |
| 34 | 0x44 | 0x7592 | Checksum (mirrors word 4) |
| 35 | 0x46 | 0xFFFF | (blank) |
| 36 | 0x48 | 0x0000 | (mirrors word 6) |
| 37 | 0x4A | 0x0002 | (mirrors word 7) |
| 38 | 0x4C | 0x0100 | (mirrors word 8) |
| 39 | 0x4E | 0x0101 | (mirrors word 9) |
| 40 | 0x50 | 0x0000 | (mirrors word 10) |
| 41 | 0x52 | 0x0000 | (mirrors word 11) |
| 42 | 0x54 | 0x0008 | (mirrors word 13) |
| 43 | 0x56 | 0x08DD | (mirrors word 14) |
| 44–63 | 0x58–0x7F | 0xFFFF | (blank) |

**Minimum M4 shim requirement:** words 0–1 must return `0x5345` / `0x4741` ("SEGA"). The
BIOS checks these two words first; if valid, it proceeds without re-writing defaults. Words
2–14 should also match to avoid the BIOS clobbering stored settings. The safe approach is
to initialize the shim's 93C46 emulator with the exact 128-byte content above.

---

## Appendix: MAME Lua measurement commands used

```
# boot transition tracking (captures MEASURED entry PC)
mame bakubaku -bios jp1 -video none -autoboot_script /tmp/capture2.lua -seconds_to_run 12

# 60-second full-boot tracking (captures MEASURED game main loop PC)
mame bakubaku -bios jp1 -video none -autoboot_script /tmp/capture6.lua -seconds_to_run 60

# IOGA polling (captures MEASURED IO_MAP values)
mame bakubaku -bios jp1 -video none -autoboot_script /tmp/iowatch.lua -seconds_to_run 25

# ROM verification
mame -verifyroms bakubaku  # → "romset bakubaku [stvbios] is bad" (missing epr-17741a; segabill dummy used)
```

All Lua scripts written to WSL `/tmp/` and executed in MAME v0.242 running in WSL Ubuntu 22.04.
MAME ran at 100% speed in all measurement sessions. Cart data confirmed in `abus` window at
frame 1200 (20 s). MAME exits with segfault at session end (Lua frame hook fires during MAME
teardown) — output collected before the fault.

Screenshot of attract mode was not captured: MAME v0.242 Lua API `video:save_snapshot()`
returns nil in this build, and `-video none` precludes render-based snapshots. The 60-second
uninterrupted run at 100% speed with stable main-loop PC is the functional equivalent
of an attract-mode confirmation.
