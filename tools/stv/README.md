# Baku Baku ROM packer

Build a deterministic 32 MB SAROO-STV cart image from the five extracted,
legally obtained Baku Baku IC dumps:

```text
python tools/stv/pack_bakubaku.py ROM_DIRECTORY bakubaku-saroo.bin \
  --boot-overlay stv-trampoline/trampoline.bin \
  --native-hle stv-native-hle/stv-native-hle.bin
```

Build the opt-in game-entry image by selecting the run trampoline:

```text
make -C stv-trampoline test-run
python tools/stv/pack_bakubaku.py ROM_DIRECTORY bakubaku-saroo-run.bin \
  --boot-overlay stv-trampoline/trampoline-run.bin \
  --native-hle stv-native-hle/stv-native-hle.bin
```

The packer validates each size and SHA-1, applies the same byte placement and
word swaps as the verified MAME/Yabause mapping, embeds the optional boot
trampoline at image offset 31 MB, and writes a JSON manifest next
to the image. The optional native HLE module is placed at image offset 20 MB,
visible through CS1 at Saturn address `0x04400000`.
ROM files and generated images must not be committed.

Copy the generated 32 MB `.bin` files to `/SAROO/STV/` on the SD card. Do not
copy `trampoline.bin` by itself. No ST-V BIOS file is used by either image.

Current SAROO PCBs expose only AA0-AA23 to the FPGA. Firmware therefore maps
image offsets 0-16 MB through CS0 and offsets 16-32 MB through CS1. Baku Baku
still requires a software relocation of references from `0x03000000` to
`0x04000000`; the manifest records this requirement.

Run the synthetic-data tests with:

```text
python -m unittest discover -s tools/stv/tests -v
```
