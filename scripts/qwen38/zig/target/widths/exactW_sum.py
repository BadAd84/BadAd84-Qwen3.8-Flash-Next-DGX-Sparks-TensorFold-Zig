#!/usr/bin/env python3
"""exactW_sum.py EXACT_DIR [RECEIPT_DIR] - the widths step's exactness: each equality per arm (main, branch) from
exactW.sh's outputs, and each branch reply against main's (same request, same boot kind). With RECEIPT_DIR, also the
receipt arms' bench_concurrent alone+serial token hashes against M1's. Loaders are exact0014_sum.py's."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "work" / "target"))
from exact0014_sum import bench, counts, drafts, resumes  # noqa: E402

ARMS = ("main", "branch")


def main():
    out = Path(sys.argv[1])
    data = {}
    for arm in ARMS:
        d = out / arm
        data[arm] = {"conc": bench(f"{d}/on/concurrent.json"), "gold": bench(f"{d}/on/golden.json"),
                     "d_on": drafts(f"{d}/on/drafts.json"), "d_off": drafts(f"{d}/off/drafts.json"),
                     "res": resumes(f"{d}/off/fresh.json", f"{d}/on/turns.json")}
    print("| check | measure | main | branch |")
    print("|---|---|---|---|")

    def show(check, measure, cell):
        print(f"| {check} | {measure} | " + " | ".join(cell(data[a]) for a in ARMS) + " |")

    def serial(key, temp):
        def cell(a):
            b = a[key]
            return "missing" if b is None or temp not in b["serial"] else f"{counts(b['serial'][temp])} ({b['tokens']} tok)"
        return cell

    def alone(key, temp):
        def cell(a):
            b = a[key]
            return "missing" if b is None or temp not in b["alone"] else f"{counts(b['alone'][temp])}, {b['failed']} failed"
        return cell

    def drafted(key):
        def cell(a):
            d = a[key]
            if d is None:
                return "missing"
            acc = [x for x in d["accepted"] if x is not None]
            return f"{d['equal']}/{d['n']} equal ({','.join(d['basis'])}); accepted {min(acc, default=None)}-{max(acc, default=None)} a reply"
        return cell

    def resumed(a):
        r = a["res"]
        return "missing" if r is None else f"{r['ok']}/{r['n']} equal ({','.join(r['basis'])})" + (f"; {r['problems']}" if r["problems"] else "")

    show("drafted == draft:false", "bench_concurrent --serial, code+chat, greedy", serial("conc", 0.0))
    show("drafted == draft:false", "bench_concurrent --serial, code+chat, temperature 1.0", serial("conc", 1.0))
    show("drafted == draft:false", "bench_concurrent --serial, six golden, greedy", serial("gold", 0.0))
    show("drafted == draft:false", "served_exactness drafts, cache on", drafted("d_on"))
    show("drafted == draft:false", "served_exactness drafts, cache off", drafted("d_off"))
    show("resumed == fresh", "served_exactness turns (on) against fresh (off)", resumed)
    show("concurrent == solo", "bench_concurrent --alone, code+chat, 1/2/4, greedy", alone("conc", 0.0))
    show("concurrent == solo", "bench_concurrent --alone, code+chat, 1/2/4, temperature 1.0", alone("conc", 1.0))
    show("concurrent == solo", "bench_concurrent --alone, six golden, 1/2/4/6, greedy", alone("gold", 0.0))
    print()
    print("Branch replies against main's (same request, same boot kind):")
    ref, a = data["main"], data["branch"]
    for key in ("conc", "gold"):
        if a[key] and ref[key]:
            keys = sorted(set(a[key]["hashes"]) & set(ref[key]["hashes"]), key=str)
            same = sum(1 for k in keys if a[key]["hashes"][k] == ref[key]["hashes"][k] and a[key]["hashes"][k][0])
            print(f"- {key}: alone+serial token hashes {same}/{len(keys)} equal")
    for key in ("d_on", "d_off"):
        if a[key] and ref[key]:
            keys = sorted(set(a[key]["ids"]) & set(ref[key]["ids"]))
            same = sum(1 for k in keys if a[key]["ids"][k] == ref[key]["ids"][k] and a[key]["ids"][k])
            print(f"- {key}: plain token ids {same}/{len(keys)} equal")
    if a["res"] and ref["res"]:
        for part in ("first", "resumed"):
            keys = sorted(set(a["res"][part]) & set(ref["res"][part]))
            same = sum(1 for k in keys if a["res"][part][k] == ref["res"][part][k] and a["res"][part][k])
            print(f"- turn {part}: token ids {same}/{len(keys)} equal")
    if len(sys.argv) > 2:
        rec = Path(sys.argv[2])
        m1 = bench(f"{rec}/M1/conc_t0.json")
        print()
        print("Receipt arms' bench_concurrent alone+serial token hashes (widest cell, first rep) against M1's:")
        for arm in ("B1", "B2", "M2"):
            b = bench(f"{rec}/{arm}/conc_t0.json")
            if b and m1:
                keys = sorted(set(b["hashes"]) & set(m1["hashes"]), key=str)
                same = sum(1 for k in keys if b["hashes"][k] == m1["hashes"][k] and b["hashes"][k][0])
                print(f"- {arm}: {same}/{len(keys)} equal; alone {b['alone']}, serial {b['serial']}, failed {b['failed']}")


if __name__ == "__main__":
    main()
