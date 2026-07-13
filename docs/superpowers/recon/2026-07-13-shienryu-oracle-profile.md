# Shienryu oracle boot profile

Date: 2026-07-13

## Inputs and boundary

The authorized archive contains the three canonical program/data ROMs and the
128-byte 93C46 image recorded in `tools/stv/games/shienryu.json`. The generic
packer produces a 32 MB image with SHA-1
`8021586b6ae0d0d13fac640d6cf2c95324ddd389`. ROMs, EEPROM data, RAM dumps, and
generated images remain ignored local artifacts and are not committed.

The oracle is the local research Yabause ST-V fork using the Japanese ST-V BIOS.
The packed cart reaches the official warning, changes to the game's 320x240
video mode, displays `BACK UP RAM INITIALIZED`, and runs at PC `0x06006C18`
without an invalid opcode.

## Corrected handoff interpretation

The early transition `0x000033A2 -> 0x0601270C` is not a game entry. Bytes at
`0x0601270C` match ST-V BIOS ROM offset `0x0000A70C`; it is a BIOS routine copied
to HWRAM. This explains why the same transition appears with unrelated games.
Do not use it as a game-specific trampoline target.

The game transfer callback first appears at `0x06004100`. At that point the
registers include `R4=0x06005000` and `R5=0x22201000`, exposing the in-progress
cart-to-HWRAM transfer. The transfer completes through BIOS `0x4522` and enters
`0x06004010` with:

```text
R0=00000510 R1=22200000 R2=060040EC R3=06000254
R4=060FC000 R5=222F9000 R6=00000000 R7=06004010
R15=06100000 PR=00004516 SR=00000001
GBR=FFFFFE00 VBR=06000000
```

The pointer endpoints and the later HWRAM dump agree on this copy:

```text
image 0x00200000..0x002F9000 (length 0xF9000)
  -> HWRAM 0x06003000..0x060FC000
entry 0x06004010
```

At a later game frame, hundreds of thousands of 32-byte windows retain the
constant mapping `image_offset = hwram_offset + 0x001FD000`. Runtime-cleared,
initialized, and self-modified areas account for the gaps.

## Observed native-service boundary

The trace has directly observed the following ST-V BIOS entries on the path to
the game screen: `0x0EFC`, `0x372C`, `0x3E4E`, `0x426C`, `0x4500`, and `0x4596`.
Several are already present in the Baku native redirect table, but this is only
evidence for shared service implementations. It does not authorize reuse of
Baku's hard-coded copy addresses, relocation veneers, handoff state, or game
callbacks.

A trace through game frame 1800 closed the direct game-edge set at five service
calls: `0x4596`, `0x3E4E`, `0x4500`, `0x426C`, and `0x372C`. Three additional
edges to `0x33A6`, `0x3268`, and `0x3324` had `target == PR` in the BIOS callback
ping-pong and are continuation returns, not independent services. VBlank reaches
`0x0EFC` through the resident path.

The post-load resident state differs from Baku. Shienryu installs game handlers
`0x06004632` and `0x06004744` at `0x06000A00/04`, and installs the BIOS cart
transfer entry `0x44FC` in the next three handler slots. The descriptor records
the complete measured service/handler slot set. A clean resident must replace
their semantics; copying Baku's handler constants would jump into the wrong
game routines.

The original 93C46 image is big-endian word data. The oracle reads all 64 words
correctly with that representation; pair-swapping it causes the game/BIOS to
rewrite the EEPROM and is wrong.

## Software completion boundary

The descriptor-driven cold copy, Shienryu resident, post-entry native services,
and BIOS-free oracle run are complete. Saturn battery-backed RAM supplies the
game's channel-4 data at logical base `0x20183D00`; the 1524-byte record is
valid when its first big-endian word equals the bitwise-NOT of the 16-bit sum
of all record bytes.

The remaining software policy question is operator-setting persistence. The
ST-V motherboard exposes a physical 93C46 through its control wiring, while a
SAROO cartridge does not. This does not block game boot or attract, but a
public hardware profile must decide whether to seed fixed operator defaults or
store an emulated 93C46 image elsewhere. Final electrical/timing validation is
necessarily deferred until a SAROO and Saturn are available.

## Clean native-HLE result

The descriptor-driven run trampoline now constructs the resident below
`0x06003000`, copies the measured `0xF9000` program block, and enters a
Shienryu-specific native handoff at `0x04401700`. The first clean attempt found
one missing resident API slot: game code at `0x0604A726` calls through
`[0x06000344]`; the measured value is `0x06000C0A`. Restoring
`0x06000340/344 -> 0x06000C00/0C0A` closed that exception.

With the fix, the SAROO mapping twin used the Saturn BIOS only to establish the
host machine, forced cartridge entry at `0x02000100`, closed the 4 KB FPGA-style
overlay, and executed native HLE from CS1. The first run reached Shienryu's own
`BACK UP RAM INITIALIZED` screen but exposed three additional facts:

1. The clean constructor had left backup callback slots `0x06000640/644/648`
   as generic no-ops. Shienryu now installs a native probe, the existing clean
   interleaved read/write dispatcher, and the resident dirty/ready marker.
2. The game uses battery-backed channel 4, not the constructor's zero default.
   Selecting channel 4 maps the record to `0x20183D00`.
3. Research Yabause leaves the first SMPC `INTBACK` query in a segmented
   transfer state, so the immediately following query never completes. A
   research-only synchronous completion shim is required to model the real
   Saturn SMPC behavior. This shim is not part of the SAROO image.

After those corrections, a freshly formatted backup RAM produced a valid
record (`stored 0x6521 == ~sum(0x9ADE)`) and entered the actual attract scene by
frame 300, then the ranking screen by frame 600. A later boot took the
checksum-valid `GOOD MORNING!!` branch and updated the record while preserving
its checksum. The following boot compared the saved system byte equal and
re-entered attract by frame 200. A reset-sequence run continued through frame
1200 without a Master SH-2 low-ROM edge or invalid opcode.

This closes the hardware-independent boot, backup-RAM, and reset-to-attract
work. The descriptor is now `hardware-candidate`; only operator-setting policy
and real SAROO electrical/timing validation remain.
