#!/usr/bin/env python3
"""Per-stream draft mechanism for a given cell label, both arms."""
import json
import sys

ROOT = "/home/adam/work/SharedDraftsMain/out"

def main():
    lab = sys.argv[1] if len(sys.argv) > 1 else "c2"
    for arm in ("0", "1"):
        c = json.load(open(f"{ROOT}/arm{arm}/{lab}/cell.json"))
        print("=== arm", arm, lab)
        for p in c["passes"]:
            for k, r in enumerate(p["replies"]):
                s = r.get("speculative") or {}
                tps = r.get("decode_tps") or 0.0
                tpr = s.get("tokens_per_round") or 0.0
                acr = s.get("acceptance_rate") or 0.0
                print("  pass%d stream%d tps=%.1f rounds=%d drafted=%d acc=%d tpr=%.2f accrate=%.3f"
                      % (p["pass"], k, tps, s.get("rounds") or 0, s.get("drafted") or 0,
                         s.get("accepted") or 0, tpr, acr))

if __name__ == "__main__":
    main()
