"""sum15.py OUT - cells, accepted tokens a round and the noise rule over receipt0015.sh's arms.

Writes OUT/cells.csv (every cell of every arm), OUT/rule5.md (main against each branch arm, the maintainer's rule: a
cell is slower when both branch runs are under both main runs and the mean gap is over 1%) and OUT/rerun.txt (the
invocations holding a slower cell, for `receipt0015.sh BASE rerun`). Arms M3/M4, U3/U4, X3/X4, when present, are the
rerun: a cell slower in the first pair and again in the rerun pair is a loss.
"""
import csv
import json
import os
import re
import statistics
import sys

OUT = sys.argv[1]
ARMS = ["M1", "U1", "X1", "M2", "X2", "U2", "M3", "U3", "X3", "M4", "X4", "U4"]
INVOCATIONS = ["openai_t0", "openai_t1", "conc_t0", "conc_t1_s1234", "conc_t1_s2234", "conc_t1_s3234"]


def spec_sums(node, acc):
    """Sum every reply's draft counts (rounds, drafted, accepted) found anywhere under `node`, serial runs excluded."""
    if isinstance(node, dict):
        if all(isinstance(node.get(k), int) for k in ("rounds", "accepted")):
            acc[0] += node["rounds"]
            acc[1] += node["accepted"]
            acc[2] += node.get("drafted") or 0
            return
        for k, v in node.items():
            if k != "serial":
                spec_sums(v, acc)
    elif isinstance(node, list):
        for v in node:
            spec_sums(v, acc)


def metric_deltas(path):
    """Per invocation: (accepted, drafted) deltas of the server's /metrics counters around it."""
    seen = {}
    if not os.path.exists(path):
        return {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"(\S+) (before|after) (.*)", line.strip())
        if not m:
            continue
        vals = {}
        for k, v in re.findall(r"(\S*mtp_(?:drafted|accepted)_total)\S* (\d+)", m.group(3)):
            vals["accepted" if "accepted" in k else "drafted"] = int(v)
        seen.setdefault(m.group(1), {})[m.group(2)] = vals
    out = {}
    for name, pair in seen.items():
        b, a = pair.get("before"), pair.get("after")
        if b and a and "accepted" in a and "accepted" in b:
            out[name] = (a["accepted"] - b["accepted"], a.get("drafted", 0) - b.get("drafted", 0))
    return out


def openai_rows(arm, inv, data):
    rows = []
    entries = data if isinstance(data, list) else data.get("results") or data.get("cells") or []
    for e in entries:
        runs = e.get("runs") or []
        tps = [r.get("decode_tps") for r in runs if isinstance(r, dict) and isinstance(r.get("decode_tps"), (int, float))]
        val = statistics.fmean(tps) if tps else next((e[k] for k in ("decode_tps", "mean_decode_tps", "decode_tps_mean")
                                                      if isinstance(e.get(k), (int, float))), None)
        if val is None:
            print(f"sum15: {arm}/{inv}: no decode rate among {sorted(e)}", file=sys.stderr)
        acc = [0, 0, 0]
        spec_sums(runs or e, acc)
        rows.append({"arm": arm, "invocation": inv, "prompt": e.get("prompt") or e.get("name"),
                     "temperature": e.get("temperature"), "seed": "1234+rep" if inv == "openai_t1" else "",
                     "streams": 1, "aggregate_tps": val, "per_stream_tps": val, "tokens_per_chunk": None,
                     "rounds": acc[0], "accepted": acc[1], "drafted": acc[2],
                     "failed": e.get("failed", 0), "unmeasured": e.get("unmeasured", 0)})
    return rows


def concurrent_rows(arm, inv, data):
    rows = []
    seed = inv.split("_s")[1] if "_s" in inv else ""
    for c in data.get("cells", []):
        acc = [0, 0, 0]
        spec_sums({k: v for k, v in c.items() if k not in ("serial", "alone")}, acc)
        rows.append({"arm": arm, "invocation": inv, "prompt": c.get("prompt"), "temperature": c.get("temperature"),
                     "seed": seed, "streams": c.get("streams"), "aggregate_tps": c.get("aggregate_tps"),
                     "per_stream_tps": c.get("per_stream_tps"),
                     "tokens_per_chunk": (c.get("pooled") or {}).get("tokens_per_chunk"),
                     "rounds": acc[0], "accepted": acc[1], "drafted": acc[2],
                     "failed": c.get("failed"), "unmeasured": c.get("unmeasured")})
    return rows


rows, deltas = [], {}
for arm in ARMS:
    d = os.path.join(OUT, arm)
    if not os.path.isdir(d):
        continue
    deltas[arm] = metric_deltas(os.path.join(d, "metrics.txt"))
    for inv in INVOCATIONS:
        p = os.path.join(d, inv + ".json")
        if not os.path.exists(p):
            continue
        data = json.load(open(p))
        rows += openai_rows(arm, inv, data) if inv.startswith("openai") else concurrent_rows(arm, inv, data)

for r in rows:
    r["accepted_per_round"] = round(r["accepted"] / r["rounds"], 3) if r["rounds"] else None
    r["tokens_per_round"] = round(r["tokens_per_chunk"], 3) if isinstance(r["tokens_per_chunk"], (int, float)) else None
    a, dr = deltas.get(r["arm"], {}).get(r["invocation"], (None, None))
    r["inv_accepted"], r["inv_drafted"] = a, dr
    r["inv_acceptance"] = round(a / dr, 4) if a is not None and dr else None

cols = ["arm", "invocation", "prompt", "temperature", "seed", "streams", "aggregate_tps", "per_stream_tps",
        "tokens_per_round", "accepted_per_round", "rounds", "accepted", "drafted", "inv_accepted", "inv_drafted",
        "inv_acceptance", "failed", "unmeasured"]
with open(os.path.join(OUT, "cells.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow({k: (round(v, 2) if isinstance(v, float) and k in ("aggregate_tps", "per_stream_tps") else v)
                    for k, v in r.items()})

key = lambda r: (r["invocation"], r["prompt"], r["temperature"], r["seed"], r["streams"])
table = {}
for r in rows:
    if isinstance(r["aggregate_tps"], (int, float)):
        table.setdefault(key(r), {})[r["arm"]] = r["aggregate_tps"]


def verdict(cell, mains, branch):
    m = [cell[a] for a in mains if a in cell]
    b = [cell[a] for a in branch if a in cell]
    if len(m) < 2 or len(b) < 2:
        return None
    gap = (statistics.fmean(b) - statistics.fmean(m)) / statistics.fmean(m) * 100
    slower = max(b) < min(m) and gap < -1.0
    faster = min(b) > max(m) and gap > 1.0
    return gap, ("SLOWER" if slower else "faster" if faster else "level")


lines = ["| invocation | prompt | temp | seed | streams | M1 | M2 | U1 | U2 | X1 | X2 | U vs main | X vs main |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
rerun, losses = set(), []
for k in sorted(table, key=lambda k: (INVOCATIONS.index(k[0]), str(k[1]), str(k[3]), k[4] or 0)):
    cell = table[k]
    vu = verdict(cell, ["M1", "M2"], ["U1", "U2"])
    vx = verdict(cell, ["M1", "M2"], ["X1", "X2"])
    fmt = lambda v: "-" if v is None else f"{v[0]:+.1f}% {v[1]}"
    lines.append("| " + " | ".join([str(x) for x in k] + [f"{cell[a]:.1f}" if a in cell else "-" for a in
                                   ["M1", "M2", "U1", "U2", "X1", "X2"]] + [fmt(vu), fmt(vx)]) + " |")
    for arms, v in ((["U3", "U4"], vu), (["X3", "X4"], vx)):
        if v and v[1] == "SLOWER":
            rerun.add(k[0])
            again = verdict(cell, ["M3", "M4"], arms)
            if again is not None:
                losses.append((k, arms[0][0], again))
if any(any(a in c for a in ("M3", "M4")) for c in table.values()):
    lines += ["", "Rerun (M3 U3 X3 M4 X4 U4) of the cells slower in the first pair:", ""]
    lines += [f"- {k} {arm}: {g:+.1f}% {v}{' (LOSS: slower again)' if v == 'SLOWER' else ''}" for k, arm, (g, v) in losses]
with open(os.path.join(OUT, "rule5.md"), "w") as f:
    f.write("\n".join(lines) + "\n")
with open(os.path.join(OUT, "rerun.txt"), "w") as f:
    f.write("".join(f"{x}\n" for x in sorted(rerun)))
print(f"sum15: {len(rows)} rows, {len(table)} cells, rerun {sorted(rerun)}, losses {len([x for x in losses if x[2][1] == 'SLOWER'])}")
