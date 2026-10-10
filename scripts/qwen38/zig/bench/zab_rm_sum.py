#!/usr/bin/env python3
"""zab_rm_sum.py LOG: zab_rm.sh's arms side by side, ours against base.

Golden: each arm's zgold_cmp.py verdict (every golden reply byte-identical to the reference file: N/N, exit 0) and
the reference it was checked against (zab_rm.sh's "GOLD <arm> reference <file> (<kind>)" line: the Zig stock image's
replies, or the Python stock serve's own for a Python arm); boot: zab_rm.sh's BOOT ... FAILED lines; effort:
effort_check.py's verdict (the server honoured RigMark's extra body); decode (Python arms): qf_run.py's decode matrix
and pmz.py's one-client prose medians from the DECODE / PM lines; TTFT: ttft.py's section (cold 1k-120k thinking
off / on, the warm turn, idle and with 3 streams decoding; ours against base); RigMark: rigmark_sum.py's section from
the RIGMARK lines. An arm that ran (any of its lines is in the log) must have a golden verdict. Exit 1 on any golden
DIFF or missing verdict, boot failure, effort failure, decode probe exit, TTFT probe error or RigMark error."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ttft  # noqa: E402  (beside this script, in the repo and in ~/work/bench on spark6)
import rigmark_sum  # noqa: E402  (beside this script too)

ARMS = ("base", "ours")
TAGS = ("BOOT", "GOLD", "DECODE", "PM", "SHAPE", "TTFT", "EFFORT", "RIGMARK")
DECODE_LINE = re.compile(r"^client\s+(?P<kind>prose|code)\s+C=(?P<c>\d+): \S+\s+(?P<tps>[\d.]+) \[")
PM_LINE = re.compile(r" pm\d+: \d+ tok, (?P<tps>[\d.]+) tok/s \(wall\)")


def decode(lines):
    """([section lines], [errors]) from a Python arm's DECODE lines (zig_sum.py's client-side summary of its qf_run.py
    rows, "DECODE <arm> client ...") and PM lines (pmz.py); none: no section."""
    cells: dict = {}
    pm: dict = {}
    errors: list = []
    for line in lines:
        p = line.rstrip("\n").split(None, 2)
        if len(p) < 3 or p[0] not in ("DECODE", "PM"):
            continue
        tag, arm, rest = p
        e = re.fullmatch(r"exit (\d+)", rest.strip())
        if e and e[1] != "0":
            errors.append(f"{tag.lower()} {arm}: exit {e[1]}")
        m = DECODE_LINE.search(rest) if tag == "DECODE" else PM_LINE.search(rest)
        if m and tag == "DECODE":
            cells.setdefault(arm, {})[(m["kind"], int(m["c"]))] = float(m["tps"])
        elif m:
            pm.setdefault(arm, []).append(float(m["tps"]))
    if not cells and not pm:
        return [], errors
    out = ["decode (qf_run.py decode, one pass, 512 tokens, greedy, thinking off: per-request tok/s from the client's "
           "side, zig_sum.py's median; pm = pmz.py's six one-client prose requests, median of their wall tok/s)"]
    for arm in order_of(set(cells) | set(pm)):
        c = cells.get(arm, {})
        row = "; ".join(f"{kind} C1/C2/C4 " + " / ".join(f"{c[kind, n]:.1f}" if (kind, n) in c else "-"
                                                          for n in (1, 2, 4)) for kind in ("prose", "code"))
        v = sorted(pm.get(arm, []))
        pm_med = f"{(v[len(v) // 2] + v[(len(v) - 1) // 2]) / 2:.1f} (n{len(v)})" if v else "-"
        out.append(f"decode {arm}: {row}; pm prose C1 {pm_med}")
    return out, errors


def golden(lines):
    """({arm: (same, total, exit code or None)}, set of arms that ran, [errors], {arm: reference}) from the log."""
    gold: dict = {}
    refs: dict = {}
    ran: set = set()
    errors: list = []
    for line in lines:
        p = line.rstrip("\n").split(None, 2)
        if len(p) >= 2 and p[0] in TAGS:
            ran.add(p[1])
        if len(p) < 3:
            continue
        tag, arm, rest = p
        if tag == "BOOT" and rest.startswith("FAILED"):
            errors.append(f"boot {arm}: {rest}")
        elif tag == "GOLD":
            if rest.startswith("reference ") and not rest.startswith("reference created"):
                refs[arm] = rest[len("reference "):]
            m = re.search(r": (\d+)/(\d+) identical to ", rest)
            same, total, rc = gold.get(arm, (None, None, None))
            if m:
                same, total = int(m[1]), int(m[2])
            e = re.fullmatch(r"exit (\d+)", rest.strip())
            if e:
                rc = int(e[1])
            gold[arm] = (same, total, rc)
        elif tag == "EFFORT":
            if rest.startswith("effort FAILED"):
                errors.append(f"effort {arm}: {rest}")
            e = re.fullmatch(r"exit (\d+)", rest.strip())
            if e and e[1] != "0":
                errors.append(f"effort {arm}: effort_check.py exit {e[1]}")
    return gold, ran, errors, refs


def order_of(groups):
    return sorted(groups, key=lambda g: (g not in ARMS, ARMS.index(g) if g in ARMS else 0, g))


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    with open(sys.argv[1], errors="replace") as f:
        lines = f.readlines()
    start = next((ln.strip() for ln in lines if " ZABRM " in ln and " START: " in ln), None)
    if start:
        print(start)
    gold, ran, errors, refs = golden(lines)
    bad = len(errors)
    for arm in order_of(ran):
        same, total, rc = gold.get(arm, (None, None, None))
        against = f" (against {refs[arm]})" if arm in refs else ""
        if same is None or rc is None:
            print(f"golden {arm}: NO VERDICT")
            bad += 1
        elif same == total and total > 0 and rc == 0:
            print(f"golden {arm}: {same}/{total} MATCH{against}")
        else:
            print(f"golden {arm}: {same}/{total} DIFF (zgold_cmp.py exit {rc})")
            bad += 1
            if against:
                print(f"golden {arm}: checked{against}")
    d_lines, d_errors = decode(lines)
    errors += d_errors
    bad += len(d_errors)
    for e in errors:
        print(f"ERROR {e}")
    if d_lines:
        print("\n".join(d_lines))
    samples, t_errors, excluded, order = ttft.collect(lines)
    groups = order_of(order)
    ref = "base" if "base" in groups else (groups[0] if groups else None)
    print("\n".join(ttft.section(samples, t_errors, excluded, groups, ref=ref)))
    found, r_errors, r_order = rigmark_sum.collect(lines)
    r_groups = order_of(r_order)
    rm_lines, rm_bad = rigmark_sum.section(found, r_errors, r_groups,
                                           ref="base" if "base" in r_groups else None)
    print("\n".join(rm_lines))
    return 1 if bad or t_errors or rm_bad else 0


if __name__ == "__main__":
    sys.exit(main())
