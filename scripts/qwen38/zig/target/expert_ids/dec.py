#!/usr/bin/env python3
"""dec.py LOGS SLOTS BPW - expert traffic and time a decode round, from the two in-process logs, one window at a time.

The kernel log closes a window at a 300 ms launch gap and prints its table when the next window's first launch
arrives, so the expert-log lines between two tables belong to the second table's window. For each window: the
rounds the server's own `done` lines report, every expert call's rows (inverted from the plan's item bound), the
unique routed experts the plan made (items less the skipped shared slot's), their weight bytes, and the expert
kernels' booked time. SLOTS is picks a row plus the shared slot (11 ours, 6 production); BPW bytes a weight.
"""
import collections
import re
import sys

EXP = re.compile(r"^expert log: (\S+) grid (\d+) items (\d+) made (-?\d+) mats (\d+) n (\d+) k (\d+)")
KHEAD = re.compile(r"^kernel log: window ([\d.]+) ms wall, ([\d.]+) ms in kernels, (\d+) launches")
KROW = re.compile(r"^kernel log: ([\d.]+) ms (\d+) launches ([\d.]+) us each grid (\d+) (.*)$")
DONE = re.compile(r"done chatcmpl-\S+ prompt=(\d+).* rounds=(\d+)")


def rows_of(items, slots, tile):
    for r in range(1, 4097):
        p = r * slots
        if min(p, 513) + p // tile == items:
            return r
    return -1


def family(sym):
    if "fact_swiglu" in sym:
        return "fact_up"
    if "fact_down" in sym:
        return "fact_down"
    if "nvfp4_expert" in sym:
        return "up" if "ILi2ELi2E" in sym else "down"
    if "int4_kernel" in sym:
        return "up" if "ELi2ELi2ELi4EEE" in sym else "down"
    return None


def main():
    path, slots, bpw = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
    wins = []
    cur = {"calls": [], "rounds": 0, "reqs": []}
    table = None
    for line in open(path, errors="replace"):
        m = EXP.match(line)
        if m:
            cur["calls"].append((m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6)), int(m.group(7))))
            continue
        m = KHEAD.match(line)
        if m:
            table = {"wall": float(m.group(1)), "kern": float(m.group(2)), "launches": int(m.group(3)), "fam": collections.defaultdict(lambda: [0.0, 0])}
            cur["table"] = table
            wins.append(cur)
            cur = {"calls": [], "rounds": 0, "reqs": []}
            continue
        m = KROW.match(line)
        if m and table is not None:
            f = family(m.group(5))
            if f:
                table["fam"][f][0] += float(m.group(1))
                table["fam"][f][1] += int(m.group(2))
            continue
        m = DONE.search(line)
        if m:
            cur["rounds"] += int(m.group(2))
            cur["reqs"].append((int(m.group(1)), int(m.group(2))))
    wins.append(cur)
    for i, w in enumerate(wins):
        calls = w["calls"]
        if not calls:
            continue
        t = w.get("table")
        R = max(w["rounds"], 1)
        hist = collections.Counter()
        fam = collections.defaultdict(lambda: {"calls": 0, "made": 0, "uniq": 0, "bytes": 0.0})
        for name, grid, items, made, mats, n, k in calls:
            fact = "fact" in name
            r = rows_of(items, slots, 64 if fact else 16)
            shared = (r + (64 if fact else 16) - 1) // (64 if fact else 16) if r > 0 else 1
            uniq = max(made - shared, 0)
            up = "up" in name
            f = ("fact_" if fact else "") + ("up" if up else "down")
            e = fam[f]
            e["calls"] += 1
            e["made"] += made
            e["uniq"] += uniq
            e["bytes"] += uniq * n * k * mats * bpw
            if up:
                hist[r] += 1
        tb = sum(e["bytes"] for e in fam.values())
        print(f"== window {i}: rounds {w['rounds']} requests {w['reqs']} expert calls {len(calls)} "
              + (f"| kernel window {t['wall']:.0f} ms wall {t['kern']:.0f} ms in kernels {t['launches']} launches" if t else "| no kernel table (never closed)"))
        print("   rows a call (up calls): " + " ".join(f"{r}:{c}" for r, c in sorted(hist.items())))
        for f, e in sorted(fam.items()):
            ms, kc = (t["fam"].get(f, [0.0, 0]) if t else [0.0, 0])
            gbs = e["bytes"] / (ms * 1e6) if ms else 0.0
            print(f"   {f:10s} calls {e['calls']:6d} ({e['calls']/R:6.1f}/round) unique experts {e['uniq']:7d} ({e['uniq']/max(e['calls'],1):6.1f}/call)"
                  f" MB {e['bytes']/1e6:9.1f} ({e['bytes']/1e6/R:7.1f}/round) | kernel {ms:9.1f} ms {kc:6d} launches ({ms/R:6.2f} ms/round) {gbs:6.1f} GB/s")
        if t:
            km = sum(v[0] for v in t["fam"].values())
            print(f"   all experts: {tb/1e6/R:8.1f} MB/round {km/R:7.2f} ms/round {tb/(km*1e6) if km else 0:6.1f} GB/s; round in kernels {t['kern']/R:7.2f} ms, wall {t['wall']/R:7.2f} ms")


if __name__ == "__main__":
    main()
