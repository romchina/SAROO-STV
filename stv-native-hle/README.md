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

The handler entry points begin at `0x04400900`. The trampoline calls the
initializer after copying the game and installing relocation veneers, then
loads `VBR=0x06000000` and `GBR=0xFFFFFE00`. Interrupts remain masked during
this diagnostic stage.

`stv_bootstrap_handoff` reproduces the already-observed non-returning `0x4114`
transition: it seeds the top-of-HWRAM stack, writes phase `0x3470` at
`0x060002C4`, sets `[0x06000800]=1`, and jumps to `0x06010808`. It is present
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
