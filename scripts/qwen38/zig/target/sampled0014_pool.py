#!/usr/bin/env python3
"""Every boot of the sampled0014 runs pooled by arm, for sampled decode (temperature 1.0) with the drafter on.

Boot directories are grouped by name: main, main-again, main-1, main-2 are "main"; pr-default[-N] and pr-mxfp8[-N] are
the PR arms. bench_concurrent cells (code and chat, 1/2/4 streams, each boot's median of 3 reps): each arm's mean
aggregate tok/s over its boots and the boots themselves, each PR arm's mean against main's, flagged when it is below
every main boot. bench_openai (one stream, 256 tokens, seed 1234 + rep): each arm's mean over its boots for every
seed all arms ran, the PR arms against main seed by seed, and the mean over those seeds.

  python3 sampled0014_pool.py OUT.md RUN_DIR [RUN_DIR ...]
"""

import json
import re
import statistics
import sys
from pathlib import Path

ARMS = {"main": "main", "pr-default": "PR, unset", "pr-mxfp8": "PR, mxfp8"}
PR_ARMS = ("pr-default", "pr-mxfp8")
PROMPTS = ("code", "chat")
LEVELS = (1, 2, 4)
SEED = 1234


def load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def boots(runs: list[Path]) -> dict:
    """{arm: [boot directory]} for every boot directory of the runs whose name maps to an arm."""
    out = {arm: [] for arm in ARMS}
    for run in runs:
        for d in sorted(p for p in run.iterdir() if p.is_dir()):
            arm = re.sub(r"-(again|\d+)$", "", d.name)
            if arm in out:
                out[arm].append(d)
    return out


def pct(v: float, ref: float) -> str:
    return f"{(v - ref) / ref * 100:+.1f}%"


def table(head: list[str], rows: list[list[str]]) -> list[str]:
    return ["| " + " | ".join(head) + " |", "|" + "---|" * len(head), *("| " + " | ".join(r) + " |" for r in rows)]


def concurrent(arms: dict, slow: list) -> list[str]:
    head = ["prompt", "streams", *(f"{v}: mean (boots)" for v in ARMS.values()), "main range",
            *(f"{ARMS[a]} vs main" for a in PR_ARMS)]
    rows = []
    for prompt in PROMPTS:
        for n in LEVELS:
            got = {}
            for arm, dirs in arms.items():
                got[arm] = []
                for d in dirs:
                    doc = load(d / "on_t1.json") or {}
                    cell = next((c for c in doc.get("cells", []) if c["prompt"] == prompt and c["streams"] == n
                                 and c["temperature"] == 1.0), None)
                    if cell:
                        got[arm].append(cell["aggregate_tps"])
            if not got["main"]:
                continue
            ref, lo, hi = statistics.mean(got["main"]), min(got["main"]), max(got["main"])
            cols = [prompt, str(n)]
            for arm in ARMS:
                v = got[arm]
                cols.append(f"{statistics.mean(v):.1f} ({', '.join(f'{x:.1f}' for x in v)})" if v else "-")
            cols.append(f"{(hi - lo) / ref * 100:.1f}%")
            for arm in PR_ARMS:
                v = got[arm]
                if not v:
                    cols.append("-")
                    continue
                m = statistics.mean(v)
                flag = " every boot below every main boot" if max(v) < lo else " below every main boot" if m < lo else ""
                cols.append(pct(m, ref) + flag)
                if m < lo:
                    slow.append(f"{prompt}, {n} streams: {ARMS[arm]} mean {m:.1f} against main boots {lo:.1f}-{hi:.1f}")
            rows.append(cols)
    return table(head, rows)


def openai(arms: dict) -> list[str]:
    per: dict = {}  # (prompt, seed) -> {arm: [decode tok/s, one a boot]}
    names: list[str] = []
    for arm, dirs in arms.items():
        for d in dirs:
            for row in load(d / "decode_t1.json") or []:
                tps = row.get("decode_tps_all") or []
                if row.get("temperature") != 1.0 or len(tps) != len(row.get("evidence") or []):
                    continue  # a rep without a rate would shift the seeds
                if row["prompt"] not in names:
                    names.append(row["prompt"])
                for i, v in enumerate(tps):
                    per.setdefault((row["prompt"], SEED + i), {}).setdefault(arm, []).append(v)
    head = ["prompt", "seed", *(f"{v} (boots)" for v in ARMS.values()), *(f"{ARMS[a]} vs main" for a in PR_ARMS)]
    rows = []
    for name in names:
        seeds = sorted(s for (p, s), by in per.items() if p == name and all(by.get(a) for a in ARMS))
        means: dict = {a: [] for a in ARMS}
        for s in seeds:
            by = per[(name, s)]
            m = {a: statistics.mean(by[a]) for a in ARMS}
            for a in ARMS:
                means[a].append(m[a])
            rows.append([name, str(s), *(f"{m[a]:.1f} ({len(by[a])})" for a in ARMS),
                         *(pct(m[a], m["main"]) for a in PR_ARMS)])
        if seeds:
            avg = {a: statistics.mean(means[a]) for a in ARMS}
            faster = {a: sum(1 for x, y in zip(means[a], means["main"]) if x > y) for a in PR_ARMS}
            rows.append([name, f"mean of {len(seeds)} seeds", *(f"{avg[a]:.1f}" for a in ARMS),
                         *(f"{pct(avg[a], avg['main'])} ({faster[a]}/{len(seeds)} seeds faster)" for a in PR_ARMS)])
    return table(head, rows)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    out, runs = Path(sys.argv[1]), [Path(p) for p in sys.argv[2:]]
    arms = boots(runs)
    slow: list[str] = []
    lines = ["Boots: " + "; ".join(f"{ARMS[a]}: {', '.join(f'{d.parent.name}/{d.name}' for d in arms[a])}"
                                   for a in ARMS), "",
             "Sampled decode (temperature 1.0), drafter on, bench_concurrent aggregate tok/s (each boot's median of "
             "3 reps):", "", *concurrent(arms, slow), "",
             "One stream at temperature 1.0, bench_openai decode tok/s by seed, each arm's mean over its boots "
             "(boot count in brackets):", "", *openai(arms), "",
             f"PR arm means below every main boot: {len(slow)}", *(f"- {s}" for s in slow)]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"PR arm means below every main boot: {len(slow)}")


if __name__ == "__main__":
    main()
