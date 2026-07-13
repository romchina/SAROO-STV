# SAROO-STV native HLE

SH-2 native routines reserved at CS1 `0x04400000-0x0440ffff`, corresponding
to canonical cart-image offsets `0x1400000-0x140ffff`.

The first module contains the two Baku Baku source relocation veneers found by
the 3600-frame upper-ROM trace:

- game long-copy entry `0x0604afd4`;
- game memmove entry `0x06053c98`.

`stv_install_reloc_veneers` must run after the FPR body has been copied to
HWRAM and before game code starts. It installs 12-byte absolute jump stubs.
Both native routines translate only source addresses in
`0x03000000-0x033fffff` to the CS1 mirror at `0x04000000-0x043fffff`.

Build and statically verify with:

```text
make test-build
```

The remaining resource/sound initialization closure is not part of this
native module yet. Hardware reset initialization remains owned by the clean
trampoline rather than the service dispatcher.

Native clean-HLE leaf entries now implemented:

| Original BIOS entry | Native CS1 entry | Service |
|---:|---:|---|
| `0x0EFC` | `0x04400260` | vblank fixed-point clock update |
| `0x0ECC` | `0x04400100` | signed accumulate/saturate |
| `0x2C64` | `0x04400034` | memmove + SAROO source relocation |
| `0x2CAC` | `0x04400220` | memset |
| `0x372C` | `0x044001E0` | channel address |
| `0x3E4E` | `0x04400120` | packed status test |
| `0x4596` | `0x04400160` | workspace byte mirror |
| `0x4680` | `0x044001A0` | cart-layout nibble |
| `0x3842` | `0x04400400` | channel dispatch (selectors 0/10/1/20) |
| `0x4114` | `0x04400A00` | non-returning bootstrap game handoff |
| `0x426C` | `0x04400A40` | Baku handler/system transition fast path |
| `0x34C4` | `0x04400F00` | game-visible video shutdown fast path |

The same pairs are emitted as a machine-readable table at `0x04400700`,
terminated by a zero record. Selectors `0/0x10/1/0x20` of `0x3842` have been
dynamically executed with simple, signed-saturation and range-bound vectors.
The vblank steady-state and signed-overflow/strided-counter paths are also
dynamically covered.

## Clean resident foundation

`stv_resident_init` at `0x04400800` constructs the first cold-boot resident
state without copying ST-V BIOS bytes. It clears `0x06000000..0x0600EFFF`,
generates all 256 VBR entries, installs a visible exception trap, a default
IRQ return, and a register-preserving VBLANK-IN wrapper. It also connects the
verified Baku Baku vblank callback (`0x06035278`) to the native clock service
through `[0x06000610]`.

The cold twin also confirmed that both channel-address call sites dispatch
through `[0x0600063C]`; the constructor binds that slot directly to native
`0x044001E0`.
The game state-copy call through `[0x06000660]` is similarly bound to the
clean 20-byte resident copy at `0x04400D00`.

The upper VBR page doubles as the resident API table. The constructor restores
`[0x300/0x304]` as handler set/get and `[0x310/0x314]` as vector set/get,
using native getters at `0x04401100/0x04401120`. This prevents service calls
from accidentally entering the default interrupt `RTE` handler.

The handler entry points begin at `0x04400900`. The trampoline calls the
initializer after copying the game and installing relocation veneers, then
loads `VBR=0x06000000` and `GBR=0xFFFFFE00`. Interrupts remain masked during
this diagnostic stage.

The exception handler writes a versioned crash record at `0x06000B80` before
halting.  It contains VBR, GBR, MACL, MACH, PR, R0-R14, and the exception-frame
PC/SR; the legacy `0xDEADE001` marker at `0x06000BFC` remains available. Decode
a binary HWRAM dump with:

```text
python tools/stv/decode_crash.py hwram.bin
```

`stv_resident_input_poll` at `0x04401140` runs before the game VBlank callback.
It reads packed active-low A/B, C/E and F/D ports from SAROO's CS2 registers at
`0x25807020/22/24`, then publishes the original resident's active-high input
longs at `0x06002864-0x06002874` and derived system byte at `0x06000730`.
This indirection is required because the Saturn cartridge bus cannot select the
ST-V IOGA's original low-bus page at `0x00400000`.

The trampoline calls `stv_smpc_pad_init` at `0x04401200`. VBlank then advances
`stv_smpc_pad_poll` at `0x04401280` as a non-blocking state machine: one frame
issues INTBACK and a later frame consumes OREG2/3. A 60-poll timeout resets only
the pad state and never spins inside the interrupt. Saturn directions/A/B/C/X
map to ST-V P1, Start maps to Start1, and L maps to Coin1. Yabause smoke images
execute both idle and synthetic pressed vectors through the real SH-2 code.

`stv_hardware_init` at `0x04401400` purges/disables the master cache, stops SCU
DMA, masks/clears SCU interrupt state, parks Slave SH-2, resets VDP1 drawing,
and installs the measured Baku VDP2 cycle pattern. The handoff changes SCU IMS
to `0xFFFFE1FC` only immediately before it opens SR.

`stv_scsp_sound_poll` at `0x04401600` watches the SCSP 68K reset vector at
`0x25A00004`. When Baku installs a new valid vector it arbitrates with pad
INTBACK and advances a non-blocking SNDOFF/SNDON sequence, reproducing the
Yabause twin's former vector-write restart hook on real Saturn hardware. Both
commands and the Slave-SH2 park command are required by the dynamic smoke test.

`stv_bootstrap_handoff` reproduces the measured non-returning `0x4114`
transition: it builds the 32-byte frame at `0x060FFFDC`, restores the observed
register state (`GBR=0x060D28C8`, `R4=0x120`, `R5=0x20180108`,
`R7=0x45A07058`), writes phase `0x3470` at `0x060002C4`, sets
`[0x06000800]=1`, seeds the observed selector bytes at `0x06083238`, and
jumps to `0x06010808`. It is present
in the redirect metadata but the trampoline deliberately does not invoke it
until the clean hardware initialization and remaining resource/sound closure
are ready for an end-to-end cold-start attempt.

The Baku-specific `0x426C` path was captured at its sole runtime call
(`R4=0`). Its clean implementation consumes `[0x06000324]`, sets bit `0x80`
in `[0x06000824]`, preserves the handler pointers, and reproduces the observed
return registers. Concurrent changes to the vblank accumulator were excluded
from the contract. The associated display/SCU/SCSP reset is intentionally a
separate trampoline responsibility.

## Generated HWRAM veneers

The resident constructor emits clean jump veneers at every non-interrupt
HWRAM entry observed during the game-to-resident edge trace:

| HWRAM entry | Native entry | Contract |
|---:|---:|---|
| `0x06000C00` | `0x04400B00` | set SCU interrupt mask/shadow |
| `0x06000C0A` | `0x04400B20` | masked SCU interrupt update |
| `0x06000D14` | `0x04400B40` | vblank clock dispatch |
| `0x06001198` | `0x04400B60` | 16-entry resident queue pop |
| `0x0600120E` | `0x04400BA0` | system flag clear |
| `0x06001412` | `0x04400BE0` | strided word/long read/write dispatch |
| `0x06001494` | `0x04400C40` | VBR vector setter |
| `0x060014A8` | `0x04400C80` | handler-table setter |
| `0x060014C0` | `0x04400CC0` | 128-byte table copy |
| `0x060014E0` | `0x04400D00` | 20-byte state copy |

The close-packed `0xC00/0xC0A` pair uses six-byte PC-relative jump veneers;
the other entries use the standard 12-byte absolute form. Interrupt-only
edges at `0x06001Fxx/0x06002030` are replaced by native VBR handlers.

The direct `0x34C4` oracle showed three calls. Two are internal BIOS boot
passes superseded by the clean trampoline. The sole game-returning call is a
steady-state display shutdown with no HWRAM changes; `stv_video_shutdown_fast`
implements that observable contract and returns the native exception handler.

The only observed `0x4500` descriptor reconstructs FPR `+0x1000` at
`0x06010000` from the interleaved `0x02002000` view. The trampoline
pre-materializes that shifted body from the plain mirror, so this boot-only
transfer is deliberately bypassed.

Validation completed against the Yabause twin with CS0 deliberately limited to
16 MB and CS1 mapped like the current FPGA implementation. The SH-2 executed
both veneers during 70 seconds of autoplay without invalid opcodes or low-ROM
execution. Those temporary twin changes were removed after the run.

The six new leaf routines were also executed directly by Yabause's SH-2
interpreter with injected register/HWRAM vectors. Eleven return-value and memory
assertions passed; the temporary self-test harness was removed afterwards.

Finally, a 70-second integration run redirected every clean-HLE entry to these
CS1 routines. It completed without invalid opcodes, low-ROM execution or an
unimplemented service. The Yabause mapping/redirect hooks were removed after
the run.

The full clean cold path was then exercised with a temporary SAROO-equivalent
CS0/CS1 executable mapping: shifted FPR construction, native resident init,
measured `0x4114` handoff frame, and game execution ran for 60 seconds with
`STV_NOLOW` and invalid-opcode tracing enabled. No low BIOS edge, exception,
invalid opcode, or unimplemented service occurred. The temporary twin mapping
and probes were removed after the run.

## Shienryu profile

`make test-shienryu` builds `stv-native-hle-shienryu.bin`. It retains the
shared leaf services but installs Shienryu's measured VBlank/aux callbacks
(`0x06004632`, `0x06004744`), restores the mask API slots at
`0x06000340/344`, selects battery-backed channel 4, and restores the
`0x06000640/644/648` backup probe/access/mark callbacks. The interleaved word
access uses the existing clean `0x06001412` replacement. The profile exposes
the clean game handoff at `0x04401700`. Use it
only with `trampoline-shienryu-run.bin`; Baku's callback and handoff constants
remain isolated in the default image.
