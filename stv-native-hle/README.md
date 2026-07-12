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

The remaining clean-HLE service routines and cold-boot handoff constructor are
not part of this first native module yet.

Validation completed against the Yabause twin with CS0 deliberately limited to
16 MB and CS1 mapped like the current FPGA implementation. The SH-2 executed
both veneers during 70 seconds of autoplay without invalid opcodes or low-ROM
execution. Those temporary twin changes were removed after the run.
