import re
genuine={}; rte={}; other={}
for line in open("/tmp/bioscall.log"):
    m=re.search(r"caller=(\w+) PR=(\w+) -> bios=(\w+)",line)
    if not m: continue
    caller,pr,tgt=m.group(1),m.group(2),m.group(3)
    if pr.startswith("06"):           # PR returns to game code = genuine JSR/BSR call
        genuine.setdefault(tgt,set()).add(caller)
    elif caller.startswith("0600205") or caller.startswith("06001F"):
        rte[tgt]=caller               # interrupt-return contamination
    else:
        other.setdefault(tgt,set()).add((caller,pr))
print("=== GENUINE game->BIOS routine calls (HLE work list) ===")
for t in sorted(genuine): print(f"  bios 0x{t.upper()}   <- callers {sorted(genuine[t])}")
print(f"\n=== contamination (interrupt-return into BIOS): {len(rte)} targets (ignore) ===")
print(f"\n=== OTHER (caller HWRAM, PR in BIOS -- tail-jump/RTS into BIOS, review) ===")
for t in sorted(other): print(f"  bios 0x{t.upper()}   <- {sorted(other[t])}")
