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

## One-command virtual acceptance

From Windows, run every hardware-independent test through WSL:

```powershell
.\tools\stv\verify_virtual.ps1
```

With a directory containing the five canonical, legally obtained ROM dumps,
the same command also rebuilds and verifies both 32 MB hardware candidates:

```powershell
.\tools\stv\verify_virtual.ps1 -RomDirectory C:\path\to\bakubaku-roms `
  -OutputDirectory C:\path\to\output
```

On Linux/WSL, invoke `bash tools/stv/verify_virtual.sh` directly and pass
`--rom-dir` / `--output-dir` when canonical image generation is wanted.  A
run without ROM data still checks the packer with synthetic fixtures, a clean
Saturn menu firmware build, the MCU loader, FPGA mapping, native HLE layout,
and both trampoline variants. When
the local Yabause twin exists at `/root/yabause-stv`, it also executes native
SH-2 asynchronous SMPC smoke tests for idle and synthetic pressed-pad vectors.

GitHub Actions runs the same script with `--ci`. That mode skips only the
Saturn menu C build because Ubuntu does not package an SH-2 GCC; Python tests,
MCU host tests, the FMC/FPGA simulation, and both binutils-only SH-2 modules
still run. The full local command remains the release acceptance path.

When Keil MDK is installed at `C:\Keil_v5` and Quartus Prime Lite 25.1 at
`C:\altera_lite\25.1std`, the PowerShell wrapper also runs the vendor
acceptance automatically: a clean ARMCLANG MCU rebuild followed by a complete
Quartus Analysis & Synthesis, Fitter, Assembler, and TimeQuest flow. Run that
part alone with:

```powershell
.\tools\stv\verify_vendor.ps1
```

## Hardware bring-up helpers

PowerShell helpers for SD deployment, UART capture, J-Link MCU programming,
and USB-Blaster FPGA programming live beside this README. See
`docs/STV-HARDWARE-BRINGUP.md` for the exact workflow and the important
Saturn-HWRAM/J-Link boundary.
