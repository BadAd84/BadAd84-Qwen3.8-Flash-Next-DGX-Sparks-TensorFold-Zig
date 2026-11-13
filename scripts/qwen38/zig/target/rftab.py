#!/usr/bin/env python3
"""rftab.py LOG ROUNDS LABEL [NVFP4|INT4] - the expert kernels of a run as bytes, time and GB a second.

The expert log gives, for every expert launch, the items its grid covers and the items the plan really made, plus
the matrix behind one item; the kernel log gives that launch's time, joined on the grid width. Bytes are the made
items times one item's weight bytes, so an expert read twice counts twice.
"""
import collections
import re
import sys


def main() -> None:
    log, rounds, label = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    fmt = sys.argv[4] if len(sys.argv) > 4 else "NVFP4"
    per_weight = 0.5625 if fmt == "NVFP4" else 0.5 + 2.0 / 128.0
    ex = collections.defaultdict(lambda: {"made": 0, "items": 0, "bytes": 0.0, "calls": 0, "n": 0, "k": 0, "mats": 0})
    kt = collections.defaultdict(lambda: [0.0, 0])
    # a kernel row belongs to the up call or the down call by its template: ours carries M and EPI, production MATS
    rules = [
        ("nvfp4_fact_up", lambda s: "fact_swiglu" in s),
        ("nvfp4_fact_down", lambda s: "fact_down" in s),
        ("nvfp4_run_up", lambda s: "nvfp4_expert" in s and "ILi2ELi2E" in s),
        ("nvfp4_run_down", lambda s: "nvfp4_expert" in s and ("ILi1ELi0E" in s or "ILi1ELi3E" in s or "ILi1ELi1E" in s)),
        ("int4_gate_up", lambda s: "int4_kernel" in s and "ELi2ELi2ELi4EEE" in s),
        ("int4_down", lambda s: "int4_kernel" in s and "ELi2ELi2ELi4EEE" not in s),
    ]
    for line in open(log, errors="ignore"):
        m = re.search(r"expert log: (\S+) grid (\d+) items (\d+) made (-?\d+) mats (\d+) n (\d+) k (\d+)", line)
        if m:
            name = m.group(1)
            items, made, mats = int(m.group(3)), int(m.group(4)), int(m.group(5))
            n, k = int(m.group(6)), int(m.group(7))
            e = ex[name]
            real = made if made >= 0 else items
            e["made"] += real
            e["items"] += items
            e["bytes"] += real * n * k * mats * per_weight
            e["calls"] += 1
            e["n"], e["k"], e["mats"] = n, k, mats
            continue
        m = re.search(r"kernel log: ([\d.]+) ms (\d+) launches [\d.]+ us each grid (\d+) (.*)$", line)
        if m:
            ms, calls, sym = float(m.group(1)), int(m.group(2)), m.group(4).strip()
            for name, pick in rules:
                if pick(sym):
                    e = kt[name]
                    e[0] += ms
                    e[1] += calls
                    break
            continue

    print("== %s: %d rounds, %s weights at %.4f bytes a weight" % (label, rounds, fmt, per_weight))
    head = ("call", "launch/rd", "items", "made", "MB/rd", "ms/rd", "GB/s", "n", "k", "mats")
    print("   %-18s %9s %7s %7s %9s %7s %7s %6s %6s %5s" % head)
    tot_b = tot_t = 0.0
    for name, e in sorted(ex.items(), key=lambda kv: -kv[1]["bytes"]):
        ms, calls = kt.get(name, [0.0, 0])
        gb = (e["bytes"] / 1e9) / (ms / 1000) if ms > 0 else 0.0
        tot_b += e["bytes"]
        tot_t += ms
        print("   %-18s %9.1f %7.0f %7.0f %9.1f %7.2f %7.0f %6d %6d %5d" % (
            name, e["calls"] / rounds, e["items"] / e["calls"], e["made"] / e["calls"],
            e["bytes"] / 1e6 / rounds, ms / rounds, gb, e["n"], e["k"], e["mats"]))
    if tot_t > 0:
        print("   total %.0f MB a round in %.2f ms a round -> %.0f GB a second" % (
            tot_b / 1e6 / rounds, tot_t / rounds, (tot_b / 1e9) / (tot_t / 1000)))


if __name__ == "__main__":
    main()
