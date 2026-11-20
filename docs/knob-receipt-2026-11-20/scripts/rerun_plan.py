"""rerun_plan.py OUT --plan PLAN.tsv [--window NAME] [--write]

The noise rule's second half: a cell flagged "slower" gets one rerun of its invocation in the same window, and a
repeat of slower is a loss. This reads the analyzer's summary.json and writes a rerun plan (plans/<window>r.tsv) that
reruns only the flagged treatments, each bracketed by two main runs, with the treatment's overrides copied from the
window's own plan so the rerun is the same setting.

Exit 0 and write nothing when no cell is flagged. Exit 1 when the analysis is missing.
"""
import json
import os
import sys
import argparse


def read_plan(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        while len(parts) < 5:
            parts.append("")
        arm, passes, par, ctx, ovs = parts[:5]
        rows.append({"arm": arm, "passes": passes, "par": par, "ctx": ctx, "ovs": ovs})
    return rows


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("out")
    p.add_argument("--plan", required=True, help="the window's own plan, for each treatment's overrides")
    p.add_argument("--window", default="")
    p.add_argument("--write", action="store_true")
    a = p.parse_args(argv)
    summary_path = os.path.join(a.out, "analysis", "summary.json")
    if not os.path.exists(summary_path):
        print("no analysis at", summary_path, file=sys.stderr)
        return 1
    s = json.load(open(summary_path, encoding="utf-8"))
    flagged = {}
    for r in s.get("decode_cells", []) + s.get("ttft_cells", []):
        if r.get("verdict") == "slower":
            flagged.setdefault(r["treatment"], []).append(r["cell"])
    plan = {r["arm"]: r for r in read_plan(a.plan)}
    window = a.window or os.path.basename(a.out.rstrip("/"))
    lines = []
    if flagged:
        base = [r["arm"] for r in read_plan(a.plan)][0]
        first = plan[base]
        lines.append("\t".join([first["arm"], first["passes"], first["par"], first["ctx"], ""]))
        for t in sorted(flagged):
            members = [m for m in (t, t + "b") if m in plan]
            if not members:
                print(f"treatment {t} has no plan row: skipped", file=sys.stderr)
                continue
            for m in members:
                r = plan[m]
                lines.append("\t".join([m, r["passes"], r["par"], r["ctx"], r["ovs"]]))
        last = plan[s["base_arms"][-1]]
        lines.append("\t".join([last["arm"], last["passes"], last["par"], last["ctx"], ""]))
    for t, cells in sorted(flagged.items()):
        print(f"flagged {t}: {len(cells)} slower cells, e.g. {cells[0]}")
    if not lines:
        print("no cell flagged slower: no rerun plan")
        return 0
    text = "\n".join(lines) + "\n"
    if a.write:
        path = os.path.join(os.path.dirname(a.plan), window + "r.tsv")
        open(path, "w", encoding="utf-8", newline="\n").write(text)
        print("wrote", path, len(lines), "arms")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
