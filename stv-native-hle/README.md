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

The two complex clean-HLE services listed below and the cold-boot handoff
constructor are not part of this native module yet.

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

The same pairs are emitted as a machine-readable table at `0x04400300`,
terminated by a zero record. Selectors `0/0x10/1/0x20` of `0x3842` have been
dynamically executed with simple, signed-saturation and range-bound vectors.
The vblank steady-state and signed-overflow/strided-counter paths are also
dynamically covered.

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
