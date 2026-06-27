#!/usr/bin/env python3
# Analyze BIOS-resident HWRAM region in fs_hwram.bin (big-endian, base 0x06000000).
import struct
data = open("/root/yabause-stv/stvstate/fs_hwram.bin","rb").read()
def L(off): return struct.unpack(">I", data[off:off+4])[0]
def W(off): return struct.unpack(">H", data[off:off+2])[0]
def B(off): return data[off]

print("=== SH-2 exception/interrupt vector table (VBR=0x06000000) ===")
names={0:"power-reset PC",1:"power-reset SP",2:"manual-reset PC",3:"manual-reset SP",
       4:"general illegal instr",6:"slot illegal",9:"CPU addr err",10:"DMA addr err",
       11:"NMI",12:"UBC"}
for v in [0,1,2,3,4,6,9,10,11,12]:
    print(f"  vec[{v:2}] @0x{v*4:03X} = 0x{L(v*4):08X}  {names.get(v,'')}")
print("  ... auto-vector region (0x40..) interrupt handlers:")
for v in [0x40,0x41,0x42,0x43,0x44]:
    print(f"  vec[0x{v:02X}] @0x{v*4:03X} = 0x{L(v*4):08X}")

print("\n=== handler pointer table region (recon: 0x06000610 vblank ptr, 0x06000900+vec*4) ===")
for off in [0x300,0x304,0x340,0x348,0x510,0x52C,0x544,0x610,0x640,0x644]:
    print(f"  [0x060006{off:02X} -> wait] [0x{0x06000000+off:08X}] = 0x{L(off):08X}")
print("  handler dispatch table 0x06000900-0x06000A10 (indexed by vec<<2):")
for off in range(0x900,0xA14,4):
    val=L(off)
    if val: print(f"    [0x{0x06000000+off:08X}] = 0x{val:08X}")

print("\n=== BIOS work variables referenced by HLE routines ===")
for off,desc in [(0x650,"byte idx (0x372C/0x3842)"),(0x656,"byte idx (0x44FC ROM xfer)"),
                 (0x658,"word status (0x3E4E)"),(0x65A,"byte array base (0x4596)"),
                 (0x758,"long vblank accumulator (0xEFC)")]:
    print(f"  [0x{0x06000000+off:08X}] = B:0x{B(off):02X} W:0x{W(off):04X} L:0x{L(off):08X}  {desc}")

print("\n=== find BIOS-resident / game-code boundary ===")
# Heuristic: scan 0x1000-byte blocks; BIOS-resident region is below game code start.
# Game main is ~0x06010006. Show whether 0x0600F000-0x06010000 is code/data.
for base in [0x0000,0x1000,0x2000,0x3000,0xC00,0xD00,0xF000,0xF200,0xF360]:
    chunk=data[base:base+16]
    print(f"  @0x{0x06000000+base:08X}: "+" ".join(f"{b:02X}" for b in chunk))
print("\n  (game copy target per recon: fpr[k]->HWRAM[k+0x0600F000]; R1@handoff=0x0600F366)")
