#!/usr/bin/env python3
"""ids.py LOGS TOPK BPW - unique experts, passes, bytes and time a decode round, from the expert log's ids lines.

The decode window is every expert launch after the kernel log's first table (the boot self-check) and before its
second (closed by a trailing request). A launch's layer is its weight base; the main layers are the 48 bases of the
first boot forward, any other base is the drafter's MTP layer. Rows a call are the shared slot's pairs (expert 512,
skipped by the routed kernels). Unique bytes count each (layer, expert) once a call (once a round for the drafter's
steps); launch bytes count every item, so their ratio is the passes an expert's weights take.
"""
import collections
import re
import sys

LINE = re.compile(r"^expert log: (\S+) grid (\d+) items (\d+) made (-?\d+) mats (\d+) n (\d+) k (\d+) us ([\d.]+) w ([0-9a-f]+)(?: ids(.*))?")
DONE = re.compile(r"done chatcmpl-\S+ prompt=(\d+).* rounds=(\d+)")
SKIP = 512


def main():
    path, topk, bpw = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
    up_b, dn_b = 2 * 640 * 2560 * bpw, 640 * 2560 * bpw
    tables, calls, rounds, main_w = 0, [], 0, []
    pending = None
    for line in open(path, errors="replace"):
        if line.startswith("kernel log: window"):
            tables += 1
            continue
        m = DONE.search(line)
        if m and tables == 1:
            rounds += int(m.group(2))
            continue
        m = LINE.match(line)
        if not m:
            continue
        name, grid, items, made, us, w = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4)), float(m.group(8)), m.group(9)
        if "up" in name:
            ids = [tuple(int(x) for x in t.split(":")) for t in (m.group(10) or "").split()]
            if tables == 0 and len(main_w) < 48 and w not in main_w:
                main_w.append(w)
            pending = {"name": name, "grid": grid, "items": items, "made": made, "us": us, "w": w, "ids": ids, "win": tables}
        elif pending is not None:
            pending["down"] = (name, grid, us)
            if pending["win"] == 1:
                calls.append(pending)
            pending = None
    mains = set(main_w)
    R = max(rounds, 1)
    # rounds of the decode window: a verify forward (main bases), then the drafter's steps up to the next forward
    ver, dra, cur_draft, draft_rounds = [], [], [], []
    for c in calls:
        if c["w"] in mains:
            if cur_draft:
                draft_rounds.append(cur_draft)
                cur_draft = []
            ver.append(c)
        else:
            cur_draft.append(c)
            dra.append(c)
    if cur_draft:
        draft_rounds.append(cur_draft)

    def stats(cs):
        rows = picks = uniq = items = 0
        t_up = t_dn = 0.0
        grids = units = 0
        for c in cs:
            r = sum(n for e, n in c["ids"] if e == SKIP)
            routed = [(e, n) for e, n in c["ids"] if e != SKIP]
            rows += r
            picks += r * topk
            uniq += len({e for e, _ in routed})
            items += len(routed)
            t_up += c["us"]
            t_dn += c["down"][2]
            grids += c["grid"]
        return rows, picks, uniq, items, t_up, t_dn, grids

    print(f"decode window: rounds {rounds}, expert calls {len(calls)}, main bases {len(mains)}, drafter calls {len(dra)} in {len(draft_rounds)} groups")
    rows, picks, uniq, items, t_up, t_dn, grids = stats(ver)
    n = max(len(ver), 1)
    print(f"verify: {len(ver)/48/R:.3f} forwards a round, {rows/n:.2f} rows a layer call, {picks/n:.1f} picks, {uniq/n:.1f} unique experts"
          f" ({uniq/max(picks,1)*100:.0f}% of picks), {items/max(uniq,1):.3f} passes an expert")
    ub, lb = uniq * (up_b + dn_b), items * (up_b + dn_b)
    print(f"verify a round: unique {ub/1e6/R:.1f} MB, launched {lb/1e6/R:.1f} MB, up {t_up/1e3/R:.2f} ms + down {t_dn/1e3/R:.2f} ms ="
          f" {(t_up+t_dn)/1e3/R:.2f} ms; GB/s up {items*up_b/max(t_up,1e-9)/1e3:.1f} down {items*dn_b/max(t_dn,1e-9)/1e3:.1f}")
    # verify by rows a call
    by = collections.defaultdict(list)
    for c in ver:
        by[sum(n for e, n in c["ids"] if e == SKIP)].append(c)
    print("  rows | calls | unique | passes | up us | down us | up GB/s | down GB/s | up grid | down grid")
    for r in sorted(by):
        cs = by[r]
        u = sum(len({e for e, _ in c["ids"] if e != SKIP}) for c in cs) / len(cs)
        it = sum(len([1 for e, _ in c["ids"] if e != SKIP]) for c in cs) / len(cs)
        tu = sum(c["us"] for c in cs) / len(cs)
        td = sum(c["down"][2] for c in cs) / len(cs)
        print(f"  {r:4d} | {len(cs):5d} | {u:6.1f} | {it/max(u,1e-9):6.3f} | {tu:6.1f} | {td:7.1f} | {it*up_b/tu/1e3:7.1f} | {it*dn_b/td/1e3:9.1f} |"
              f" {sum(c['grid'] for c in cs)/len(cs):7.0f} | {sum(c['down'][1] for c in cs)/len(cs):7.0f}")
    if dra:
        rows, picks, uniq, items, t_up, t_dn, grids = stats(dra)
        ru = sum(len({e for c in g for e, _ in c["ids"] if e != SKIP}) for g in draft_rounds)
        print(f"drafter: {len(dra)/R:.2f} steps a round, {rows/len(dra):.2f} rows a step, {uniq/len(dra):.1f} unique a step,"
              f" {ru/R:.1f} unique a round over its steps, {items/max(ru,1):.3f} passes an expert a round")
        print(f"drafter a round: unique {ru*(up_b+dn_b)/1e6/R:.1f} MB, launched {items*(up_b+dn_b)/1e6/R:.1f} MB,"
              f" {(t_up+t_dn)/1e3/R:.2f} ms; GB/s up {items*up_b/max(t_up,1e-9)/1e3:.1f} down {items*dn_b/max(t_dn,1e-9)/1e3:.1f}")


if __name__ == "__main__":
    main()
