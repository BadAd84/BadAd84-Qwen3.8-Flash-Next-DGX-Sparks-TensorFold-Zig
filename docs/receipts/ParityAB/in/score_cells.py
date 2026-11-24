#!/usr/bin/env python3
"""score_cells.py --root OUT - the declared rerun rule, applied to the cells measured so far.

The rule is declared in window.sh's header before any cell exists, and this file is its only implementation:

  R1  a decode cell whose three passes' aggregate spans more than 5% (max/min - 1) is re-measured;
  R2  a decode cell with a failed pass (a DEC ... UNMEASURED line) or fewer than three passes is re-measured;
  R3  a pair of cells whose arm ratio is within 1% is re-measured on BOTH arms (a claimed tie must be resolved by a
      second boot, never read off one boot a side);
  R4  a TTFT case with fewer than two unflagged samples, with an excluded sample, or whose unflagged samples span
      more than 10% is re-measured;
  R5  the warm case with no unflagged sample reporting cached tokens, or with a flagged one, is re-measured.

Output: one `RERUN <arm> c<C> <reason>` line per cell to re-measure (deduplicated per arm and level), then
`SCORE-SUMMARY cells <n> rerun <n>`; --final only labels the run as the post-rerun verdict.
"""
from __future__ import annotations
import argparse
import glob
import os
import re
import statistics
import sys

DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                 r"tok/wall ([\d.]+)")
UNMEASURED = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): UNMEASURED")
SUMMARY = re.compile(r"^summary (\S+) (\S+) n (\d+)(?: ttft med ([\d.]+))?(?:.*excluded (\d+))?")
SAMPLE = re.compile(r"^sample (\S+) (\S+) ttft ([\d.]+) .*?prompt (\d+) cached (\d+) .*$")
FLAGGED = re.compile(r"NOTCOLD|NOTWARM|NOLOAD")
CASES = ("cold1k-off", "cold1k-on", "cold8k-off", "cold8k-on", "cold32k-off", "cold32k-on", "warm2k")
SPREAD_DEC = 0.05
SPREAD_TTFT = 0.10
TIE = 0.01


def last_run(root: str, arm: str, c: int) -> str | None:
    runs = []
    for path in glob.glob(os.path.join(root, arm, f"c{c}", "run*")):
        m = re.search(r"run(\d+)$", path)
        if m:
            runs.append((int(m[1]), path))
    return sorted(runs)[-1][1] if runs else None


def read(path: str) -> str:
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def dec_cells(run: str) -> dict[str, dict]:
    cells: dict[str, dict] = {}
    for line in read(os.path.join(run, "dec.log")).splitlines():
        m = DEC.match(line)
        if m:
            cell = cells.setdefault(m[2], {"agg": [], "med": [], "wall": [], "failed": 0})
            cell["agg"].append(float(m[6]))
            cell["med"].append(float(m[4]))
            cell["wall"].append(float(m[7]))
            continue
        m = UNMEASURED.match(line)
        if m:
            cells.setdefault(m[2], {"agg": [], "med": [], "wall": [], "failed": 0})["failed"] += 1
    return cells


def ttft_cells(run: str) -> dict[str, dict]:
    cells: dict[str, dict] = {}
    for line in read(os.path.join(run, "ttft.out")).splitlines():
        m = SUMMARY.match(line)
        if m:
            if m[2] != "idle":          # this window measures the idle column; a loaded sample is a different case
                continue
            cell = cells.setdefault(m[1], {"n": 0, "med": None, "excluded": 0, "samples": []})
            cell["n"] = int(m[3])
            cell["med"] = float(m[4]) if m[4] else None
            cell["excluded"] = int(m[5] or 0)
            continue
        m = SAMPLE.match(line)
        if m:
            if m[2] != "idle":
                continue
            cell = cells.setdefault(m[1], {"n": 0, "med": None, "excluded": 0, "samples": []})
            cell["samples"].append({"ttft": float(m[3]), "prompt": int(m[4]), "cached": int(m[5]),
                                    "flagged": bool(FLAGGED.search(line))})
    return cells


def spread(xs: list[float]) -> float:
    xs = [x for x in xs if x > 0]
    return (max(xs) / min(xs) - 1) if len(xs) > 1 else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--levels", default="1,2,4,6,8")
    ap.add_argument("--final", action="store_true")
    args = ap.parse_args()
    levels = [int(x) for x in args.levels.split(",")]
    rerun: dict[tuple[str, int], list[str]] = {}

    def add(arm: str, c: int, reason: str) -> None:
        rerun.setdefault((arm, c), []).append(reason)

    dec: dict[tuple[str, int], dict[str, dict]] = {}
    for arm in ("P", "D"):
        for c in levels:
            run = last_run(args.root, arm, c)
            if not run:
                add(arm, c, "no-run")
                continue
            cells = dec_cells(run)
            dec[arm, c] = cells
            for kind, cell in cells.items():
                if cell["failed"]:
                    add(arm, c, f"R2 {kind} unmeasured pass")
                elif len(cell["agg"]) < 3:
                    add(arm, c, f"R2 {kind} only {len(cell['agg'])} passes")
                if spread(cell["agg"]) > SPREAD_DEC:
                    add(arm, c, f"R1 {kind} spread {spread(cell['agg']):.1%}")
            for case, cell in ttft_cells(run).items():
                if case not in CASES:
                    continue
                good = [s for s in cell["samples"] if not s["flagged"]]
                if cell["n"] < 2 or cell["excluded"]:
                    add(arm, c, f"R4 {case} n {cell['n']} excluded {cell['excluded']}")
                if spread([s["ttft"] for s in good]) > SPREAD_TTFT:
                    add(arm, c, f"R4 {case} spread {spread([s['ttft'] for s in good]):.1%}")
                if case == "warm2k" and (cell["excluded"] or (cell["n"] and not any(s["cached"] for s in good))):
                    add(arm, c, "R5 warm2k not served from cache")

    for c in levels:
        p, d = dec.get(("P", c)), dec.get(("D", c))
        if not p or not d:
            continue
        for kind in ("prose", "code"):
            if kind in p and kind in d and p[kind]["agg"] and d[kind]["agg"]:
                ratio = statistics.median(d[kind]["agg"]) / statistics.median(p[kind]["agg"])
                if abs(ratio - 1) < TIE:
                    add("P", c, f"R3 {kind} tie {ratio:.3f}")
                    add("D", c, f"R3 {kind} tie {ratio:.3f}")

    for (arm, c), reasons in sorted(rerun.items()):
        print(f"RERUN {arm} c{c} " + "; ".join(dict.fromkeys(reasons)))
    print(f"SCORE-SUMMARY cells {len(dec)} rerun {len(rerun)}" + (" final" if args.final else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
