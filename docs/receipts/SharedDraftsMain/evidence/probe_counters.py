#!/usr/bin/env python3
"""List every (arm, cell, pass) where the /metrics drafted delta differs from the reply-summed drafted."""
import glob
import json
import os

ROOT = "/home/adam/work/SharedDraftsMain/out"

def main():
    bad = []
    total = 0
    for cell in sorted(glob.glob(f"{ROOT}/arm*/c*/cell.json")):
        c = json.load(open(cell))
        if c.get("mode") != "decode":
            continue
        for p in c["passes"]:
            total += 1
            rep = p["aggregate"].get("drafted")
            met = (p.get("counters_delta") or {}).get("tensorfold:mtp_drafted_total")
            if rep != met:
                bad.append((os.path.relpath(cell, ROOT), p["pass"], rep, met, met - rep if (met is not None and rep is not None) else None))
    print(f"passes total {total}; disagreeing {len(bad)}")
    for b in bad:
        print("  ", b)

if __name__ == "__main__":
    main()
