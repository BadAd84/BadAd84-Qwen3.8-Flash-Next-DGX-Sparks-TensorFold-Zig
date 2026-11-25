#!/usr/bin/env python3
"""summarise.py - the window's headline tables: reproduction of the recorded cells, the per-cell divergence, and
each lever against both arms.

  summarise.py --root OUT [--recorded recorded-shas.json] [--md FILE]

Reads the window's own rows.jsonl tree (one a cell) with analyse.py's loader, so the definitions of "first divergent
token" and "equal" are the same as the report's. Prints markdown.
"""
from __future__ import annotations

import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import analyse  # noqa: E402


def rows_of(cells, label, c):
    return cells.get((label, c), {"prompt_ids": {}, "rows": {}})


def cell_line(cells, a, b, c, prompt):
    ra, rb = rows_of(cells, a, c)["rows"].get((prompt, 0)), rows_of(cells, b, c)["rows"].get((prompt, 0))
    if not ra or not rb:
        return None
    cmp = analyse.compare({"prompt_ids": {}, "rows": {(prompt, 0): ra}},
                          {"prompt_ids": {}, "rows": {(prompt, 0): rb}})[0]
    return cmp


def main() -> None:
    args = sys.argv[1:]
    def opt(n, d=None):
        return args[args.index(n) + 1] if n in args else d
    root = opt("--root")
    recorded = opt("--recorded")
    cells = analyse.load_cells(root)
    labels = sorted({lbl for (lbl, _c) in cells})
    cs = sorted({c for (_l, c) in cells})
    prompts = ["prose-rec0", "code-rec0", "prose-1k", "code-1k", "prose-8k"]

    out = ["# Window summary", "", f"cells: {len(cells)}, labels: {', '.join(labels)}", "",
           "## Reproduction of the recorded ParityAB cells (C=1, pass 0, j 0)", ""]
    if recorded and os.path.exists(recorded):
        rec = json.load(open(recorded, encoding="utf-8"))
        out += ["| arm | prompt | recorded sha | this window | verdict |", "|---|---|---|---|---|"]
        for arm, lbl, key in (("P", "P_a", "P-c1-run1-"), ("D", "D_a", "D-c1-run1-")):
            for prompt, kind in (("prose-rec0", "prose"), ("code-rec0", "code")):
                want = rec.get(f"{key}{kind}-pass0-j0", {})
                r = rows_of(cells, lbl, 1)["rows"].get((prompt, 0), {})
                got = r.get("sha")
                out.append(f"| {arm} | {prompt} | {str(want.get('sha'))[:16]} | {str(got)[:16]} | "
                           f"{'MATCH' if got and got == want.get('sha') else 'DIFF'} |")
    else:
        out.append("no recorded-shas.json given")

    out += ["", "## Per-cell divergence, the controls", "",
            "| C | A | B | prompt | equal | first token | A token | B token |", "|---:|---|---|---|---:|---:|---|---|"]
    for c in cs:
        for a, b in (("P_a", "D_a"), ("P_b", "D_b"), ("P_a", "P_b"), ("D_a", "D_b")):
            if (a, c) not in cells or (b, c) not in cells:
                continue
            for prompt in prompts:
                for j in range(max(1, c)):
                    ra, rb = rows_of(cells, a, c)["rows"].get((prompt, j)), rows_of(cells, b, c)["rows"].get((prompt, j))
                    if not ra or not rb:
                        continue
                    cmp = analyse.compare({"prompt_ids": {}, "rows": {(prompt, j): ra}},
                                          {"prompt_ids": {}, "rows": {(prompt, j): rb}})[0]
                    out.append(f"| {c} | {a} | {b} | {prompt} | {'yes' if cmp['equal_text'] else 'no'} | "
                               f"{cmp['token']} | {cmp['a_token_text']!r} | {cmp['b_token_text']!r} |")

    out += ["", "## Levers: each arm's boot against its own control, and against the other arm", "",
            "| lever | vs control (same arm) | vs the other arm's control (C=1) |", "|---|---|---|"]
    for lbl in labels:
        if lbl in ("P_a", "P_b", "D_a", "D_b"):
            continue
        arm = lbl.split("_")[0]
        ctrl = f"{arm}_a"
        other = "D_a" if arm == "P" else "P_a"
        def summ(a, b):
            if (a, 1) not in cells or (b, 1) not in cells:
                return "-"
            eq, n, firsts = 0, 0, []
            for prompt in prompts:
                ra, rb = rows_of(cells, a, 1)["rows"].get((prompt, 0)), rows_of(cells, b, 1)["rows"].get((prompt, 0))
                if not ra or not rb:
                    continue
                n += 1
                cmp = analyse.compare({"prompt_ids": {}, "rows": {(prompt, 0): ra}},
                                      {"prompt_ids": {}, "rows": {(prompt, 0): rb}})[0]
                eq += 1 if cmp["equal_text"] else 0
                firsts.append(f"{prompt.split('-')[0]}{prompt.split('-')[1]}:{cmp['token']}")
            return f"{eq}/{n} equal; first tokens {' '.join(firsts)}" if n else "-"
        out.append(f"| {lbl} c1 | {summ(lbl, ctrl)} | {summ(lbl, other)} |")

    # the same lever at C=8, when it has a c8 cell
    c8 = [lbl for lbl in labels if (lbl, 8) in cells]
    if c8:
        out += ["", "## C=8 cells", "", "| lever | vs control (same arm) | vs the other arm's control |", "|---|---|---|"]
        for lbl in c8:
            arm = lbl.split("_")[0]
            ctrl, other = f"{arm}_a", ("D_a" if arm == "P" else "P_a")
            def summ8(a, b):
                if (a, 8) not in cells or (b, 8) not in cells:
                    return "-"
                eq, n = 0, 0
                for prompt in prompts:
                    for j in range(8):
                        ra = rows_of(cells, a, 8)["rows"].get((prompt, j))
                        rb = rows_of(cells, b, 8)["rows"].get((prompt, j))
                        if not ra or not rb:
                            continue
                        n += 1
                        eq += 1 if ra["sha"] == rb["sha"] else 0
                return f"{eq}/{n} equal" if n else "-"
            out.append(f"| {lbl} c8 | {summ8(lbl, ctrl)} | {summ8(lbl, other)} |")

    out += ["", "## Prompt ids (the model's input) per arm", ""]
    for c in cs:
        for a, b in (("P_a", "D_a"), ("P_b", "D_b")):
            if (a, c) in cells and (b, c) in cells:
                ia, ib = cells[(a, c)]["prompt_ids"], cells[(b, c)]["prompt_ids"]
                eq = sum(1 for p in prompts if p in ia and ia.get(p) == ib.get(p))
                out.append(f"- C={c} {a} vs {b}: {eq}/{len([p for p in prompts if p in ia])} prompts render the same ids")

    text = "\n".join(out) + "\n"
    md = opt("--md")
    if md:
        os.makedirs(os.path.dirname(md), exist_ok=True)
        open(md, "w", encoding="utf-8").write(text)
    print(text)


if __name__ == "__main__":
    main()
