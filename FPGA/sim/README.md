# FPGA Simulation

iverilog-based simulation harness for `SSMaster.v` and submodules.
Used to validate Phase 1+ changes to the A-Bus / CS0 / SDRAM path
without a Quartus bitstream or real SAROO hardware.

## Running

```bash
bash run_sim.sh                # default: tb_cs0_rom
bash run_sim.sh tb_<name>      # any testbench in this directory
gtkwave tb_cs0_rom.vcd         # view waveforms
```

From Windows (WSL):

```bash
wsl -- bash -c 'cd /mnt/c/Users/mixio/Documents/GitHub/SAROO-STV/FPGA/sim && bash run_sim.sh'
```

## Layout

- `tb_<name>.v` — testbenches. One per focused scenario.
- `stubs/` — simulation-only stand-ins for Altera megafunctions
  (`mainpll`, `cdcfifo`) and for the external SDRAM chip. Stubs
  mirror the real modules' port lists but simplify behavior.
- `run_sim.sh` — compile + run wrapper.

## Adding a new testbench

1. Copy `tb_cs0_rom.v` as a starting point — it already has the
   correct DUT port wiring (long and easy to get wrong).
2. Adjust stimulus + assertions for the new scenario.
3. Run: `bash run_sim.sh tb_<name>`.

## Phase-by-phase evolution

- **Phase 1 Task 1** (current): tie-off SDRAM, just verify the
  testbench + DUT compile and exit cleanly.
- **Phase 1 Task 2**: replace `sdram_tie_off` with
  `stubs/sdram_model.v` (simplified behavioral), pre-load bytes,
  assert CS0 reads return those bytes.
- **Phase 1 Task 3**: add write-attempt stimulus, assert ROM
  mode blocks the write (re-read returns pre-load bytes, not
  the attempted write).
- **Phase 1 Task 4**: exercise `ss_rom_base` register via FSMC,
  verify base offset re-maps CS0 reads.

## Known gaps vs. real hardware

- PLL is pass-through; real mainpll generates 100 MHz mclk from 50 MHz. Any clock-ratio-sensitive bug will NOT reproduce here.
- SDRAM model is behavioral, not timing-accurate. CAS latency,
  bank precharge timing, refresh cycles are NOT enforced.
- STM32 FSMC is idle in these testbenches — FSMC-path bugs need
  real hardware or a dedicated FSMC-driver testbench.
