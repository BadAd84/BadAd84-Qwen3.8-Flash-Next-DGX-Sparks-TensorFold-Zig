#!/usr/bin/env python3
"""restack2-sum.py WINDOW_LOG... - the A/B table and the noise rule's verdicts from restack2-win.sh windows.

Cells are named <arm><run> (A1, B1, B2, A2); the DEC lines give each cell's aggregate tok/s for the prose and the code
pass and its counters. The noise rule: an arm is slower in a cell when both of its runs are under both of the other
arm's and the means differ by more than 1 percent; anything else is the same within the noise.
"""
import collections
import re
import sys

DEC = re.compile(r"DEC r2-(?P<arm>[A-Z])(?P<run>\d+)-c(?P<c>\d+) C=\d+ (?P<kind>prose|code) pass0: .*? agg (?P<agg>[\d.]+)"
                 r".*? rounds (?P<rounds>\d+) drafted (?P<drafted>\d+) accepted (?P<accepted>\d+)")


def main(argv):
    runs = collections.defaultdict(list)  # (c, kind, arm) -> [(agg, counters)]
    for path in argv[1:]:
        for line in open(path, encoding="utf-8", errors="replace"):
            m = DEC.search(line)
            if m:
                key = (int(m["c"]), m["kind"], m["arm"])
                runs[key].append((float(m["agg"]), (int(m["rounds"]), int(m["drafted"]), int(m["accepted"]))))
    print("| streams | A (with 0004) prose / code | B (without) prose / code | B against A (means) | verdict |")
    print("|---:|---|---|---|---|")
    for c in sorted({k[0] for k in runs}):
        cells, gaps, verdicts = {}, [], []
        for arm in "AB":
            cells[arm] = " / ".join(", ".join(f"{a:.1f}" for a, _ in runs[(c, kind, arm)]) for kind in ("prose", "code"))
        for kind in ("prose", "code"):
            a = [x for x, _ in runs[(c, kind, "A")]]
            b = [x for x, _ in runs[(c, kind, "B")]]
            if not a or not b:
                gaps.append("n/a")
                verdicts.append(f"{kind}: missing")
                continue
            ma, mb = sum(a) / len(a), sum(b) / len(b)
            gap = (mb - ma) / ma * 100
            gaps.append(f"{gap:+.1f}%")
            if len(a) >= 2 and len(b) >= 2 and max(b) < min(a) and -gap > 1:
                verdicts.append(f"{kind}: B slower")
            elif len(a) >= 2 and len(b) >= 2 and max(a) < min(b) and gap > 1:
                verdicts.append(f"{kind}: A slower")
            else:
                verdicts.append(f"{kind}: same")
        print(f"| {c} | {cells['A']} | {cells['B']} | {' / '.join(gaps)} | {'; '.join(verdicts)} |")
    print()
    print("counters (rounds / drafted / accepted), prose then code, each run:")
    for key in sorted(runs):
        print(f"  c={key[0]} {key[1]} {key[2]}: " + ", ".join(f"{r}/{d}/{a}" for _, (r, d, a) in runs[key]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
