#!/usr/bin/env python3
"""summarise_parity.py --root OUT [--doc doc_target.json] [--arm-ids auto] - the parity window's tables.

Reads only the run artifacts (each cell's last run, never a prose summary) and prints markdown:

  preflight      image identity, the live production identity, the env-name and launch-flag verdicts
  decode         aggregate tok/s (per-stream median), tokens/wall, arm ratios, and both arms against the
                 recorded SPEED-TARGET cells
  ttft           cold 8k and 32k (1k as the instrument control), both thinking modes, idle
  warm           the kept-100k +2k agent turn with its cached-token counts
  boot           boot seconds, sequence memory, golden, image
  token hashes   per cell, the text sha and the engine token hash, P against D at the same (pass, j)
  not taken      the cells this window did not measure

Every ratio is arm / reference, so decode ratios above 1 are faster and TTFT ratios below 1 are faster. The doc's
cells are 512-token greedy replies measured 2026-11-10; the harness, prompts and nonce scheme are the same ones
(`tfm_decode_ids.py` is the target's `tfm_decode.py` plus token hashes), so a decode ratio against the doc is a
same-method comparison while the TTFT idle column is the doc's non-bracket value.
"""
from __future__ import annotations
import argparse
import glob
import json
import math
import os
import re
import statistics
import sys

DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                 r"tok/wall ([\d.]+)")
SUMMARY = re.compile(r"^summary (\S+) (\S+) n (\d+)(?: ttft med ([\d.]+))?(?:.*excluded (\d+))?")
SAMPLE = re.compile(r"^sample (\S+) (\S+) ttft ([\d.]+) .*?prompt (\d+) cached (\d+) .*$")
FLAGGED = re.compile(r"NOTCOLD|NOTWARM|NOLOAD")
TTFT_ORDER = ("cold8k-off", "cold8k-on", "cold32k-off", "cold32k-on", "cold1k-off", "warm2k")


def read(path: str) -> str:
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def last_run(root: str, arm: str, c: int) -> str | None:
    runs = []
    for path in glob.glob(os.path.join(root, arm, f"c{c}", "run*")):
        m = re.search(r"run(\d+)$", path)
        if m:
            runs.append((int(m[1]), path))
    return sorted(runs)[-1][1] if runs else None


def med(xs):
    xs = [x for x in (xs or []) if x is not None]
    return statistics.median(xs) if xs else None


def f(v, nd=1):
    return "-" if v is None else f"{v:.{nd}f}"


def ratio(a, b):
    return None if not a or not b else a / b


def dec(run: str) -> dict[str, dict]:
    cells: dict[str, dict] = {}
    for line in read(os.path.join(run, "dec.log")).splitlines():
        m = DEC.match(line)
        if m:
            cell = cells.setdefault(m[2], {"agg": [], "med": [], "wall": [], "failed": 0})
            cell["agg"].append(float(m[6]))
            cell["med"].append(float(m[4]))
            cell["wall"].append(float(m[7]))
        elif line.split(":")[-1].strip().startswith("UNMEASURED"):
            kind = line.split()[3]
            cells.setdefault(kind, {"agg": [], "med": [], "wall": [], "failed": 0})["failed"] += 1
    return cells


def ttft(run: str) -> dict[str, dict]:
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


def meta(run: str) -> dict[str, str]:
    out = {}
    for line in read(os.path.join(run, "meta.txt")).splitlines():
        key, _, value = line.partition("=")
        out[key] = value
    return out


def hashes(run: str) -> dict[tuple[str, int, int], dict]:
    out: dict[tuple[str, int, int], dict] = {}
    for line in read(os.path.join(run, "dec.jsonl")).splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        out[(row.get("kind"), row.get("pass"), row.get("j"))] = row
    return out


def runs(root: str, levels: list[int]) -> dict[tuple[str, int], str]:
    return {(arm, c): last_run(root, arm, c) for arm in ("P", "D") for c in levels}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--doc", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "doc_target.json"))
    ap.add_argument("--levels", default="1,2,4,6,8")
    args = ap.parse_args()
    levels = [int(x) for x in args.levels.split(",")]
    doc = json.load(open(args.doc, encoding="utf-8"))
    doc_levels = doc["levels"]
    where = runs(args.root, levels)
    pre = os.path.join(args.root, "phase0")

    print("# Parity window: r5dev40 against production (spark6)\n")
    print("Arms: **P** production (`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`) and **D** `tensorfold-qwen38:r5dev40`,")
    print("one fresh boot a level each, interleaved; decode = `tfm_decode_ids.py` (the target's own harness + token")
    print("hashes), 512 greedy tokens, 3 passes; TTFT = the target's `ttft.py`, 2 reps, idle.\n")
    print("## Declared repeats and the rerun rule, as executed\n")
    print("Repeats: decode 3 passes a cell (median reported), TTFT 2 reps a case (median), warm 2 reps and both must")
    print("report cached tokens. Rule R1-R5 is in window.sh's header; score_cells.py applied it after the first pass:\n")
    for name in ("score1.txt", "rerun1.levels", "score2.txt"):
        text = read(os.path.join(args.root, name)).strip()
        if text:
            print(f"```\n{name}:\n{text}\n```")
        else:
            print(f"- `{name}`: not present")
    print()

    # ---------------- preflight ----------------
    print("## Preflight\n")
    live = read(os.path.join(pre, "live-image.txt")).split()
    if live:
        print(f"- live production before the window: `{live[0]}` `{live[1] if len(live) > 1 else ''}`")
    for arm in ("P", "D"):
        try:
            img = json.load(open(os.path.join(pre, f"img-{arm}.json"), encoding="utf-8"))[0]
            print(f"- image {arm}: `{img.get('RepoTags')}` id `{img.get('Id', '')[:21]}` "
                  f"labels kernels={img.get('Config', {}).get('Labels', {}).get('tf.kernels')}")
        except (OSError, ValueError):
            print(f"- image {arm}: no inspect captured")
    for arm in ("P", "D"):
        for line in read(os.path.join(pre, f"envstr-{arm}.txt")).splitlines():
            if line.startswith("ENVSTR"):
                print(f"- env names {arm}: {line}")
                break
        for path in (os.path.join(pre, f"flagcheck-{arm}", "flags.txt"),):
            text = read(path)
            for line in text.splitlines():
                if line.startswith(("FLAG-SUMMARY", "FLAG-FULL")):
                    print(f"- launch flags {arm}: {line}")
    for arm in ("P", "D"):
        m = re.search(r"^# model (\S+)$", read(os.path.join(pre, f"flags-{arm}.txt")), re.M)
        if m:
            print(f"- model directory {arm}: `{m[1]}`")
    if read(os.path.join(pre, "flagmatch.txt")):
        print(f"- launch flag names, dry run against the live production command: {read(os.path.join(pre, 'flagmatch.txt')).strip()}")
    print()

    # ---------------- decode ----------------
    cells = {key: dec(run) if run else {} for key, run in where.items()}
    print("## Decode, aggregate tok/s (per-stream median in brackets), median of 3 passes\n")
    print("| concurrency | P prose | D prose | D/P | P code | D code | D/P |")
    print("|---:|---|---|---:|---|---|---:|")
    for c in levels:
        p, d = cells.get(("P", c), {}), cells.get(("D", c), {})
        row = [str(c)]
        for kind in ("prose", "code"):
            pa, da = med(p.get(kind, {}).get("agg")), med(d.get(kind, {}).get("agg"))
            pm, dm = med(p.get(kind, {}).get("med")), med(d.get(kind, {}).get("med"))
            row += [f"{f(pa)} ({f(pm)})", f"{f(da)} ({f(dm)})", f(ratio(da, pa), 3)]
        print("| " + " | ".join(row) + " |")
    print()
    print("## Decode, tokens per wall second\n")
    print("| concurrency | P prose | D prose | D/P | P code | D code | D/P |")
    print("|---:|---|---|---:|---|---|---:|")
    for c in levels:
        p, d = cells.get(("P", c), {}), cells.get(("D", c), {})
        row = [str(c)]
        for kind in ("prose", "code"):
            pw, dw = med(p.get(kind, {}).get("wall")), med(d.get(kind, {}).get("wall"))
            row += [f(pw), f(dw), f(ratio(dw, pw), 3)]
        print("| " + " | ".join(row) + " |")

    def doc_at(kind: str, table: str, c: int):
        try:
            return doc["decode"][kind][table][doc_levels.index(c)]
        except (KeyError, ValueError):
            return None

    print("\n## Both arms against the recorded target (docs/SPEED-TARGET-1.2.6.md, 2026-11-10)\n")
    print("| concurrency | P prose / doc | D prose / doc | P code / doc | D code / doc |")
    print("|---:|---|---|---|---|")
    for c in levels:
        p, d = cells.get(("P", c), {}), cells.get(("D", c), {})
        row = [str(c)]
        for kind in ("prose", "code"):
            ref = doc_at(kind, "agg", c)
            row += [f(ratio(med(p.get(kind, {}).get("agg")), ref), 3),
                    f(ratio(med(d.get(kind, {}).get("agg")), ref), 3)]
        print("| " + " | ".join(row) + " |")

    gm = {"P": [], "D": []}
    for c in levels:
        p, d = cells.get(("P", c), {}), cells.get(("D", c), {})
        for kind in ("prose", "code"):
            ref = doc_at(kind, "agg", c)
            for arm, cell in (("P", p), ("D", d)):
                r = ratio(med(cell.get(kind, {}).get("agg")), ref)
                if r:
                    gm[arm].append(r)
    for arm in ("P", "D"):
        if gm[arm]:
            geo = math.exp(sum(math.log(x) for x in gm[arm]) / len(gm[arm]))
            print(f"\n{arm} against the doc over the ten aggregate cells: geometric mean **{geo:.3f}** "
                  f"(min {min(gm[arm]):.3f}, max {max(gm[arm]):.3f})")

    dg = []
    for c in levels:
        p, d = cells.get(("P", c), {}), cells.get(("D", c), {})
        for kind in ("prose", "code"):
            r = ratio(med(d.get(kind, {}).get("agg")), med(p.get(kind, {}).get("agg")))
            if r:
                dg.append(r)
    if dg:
        print(f"\nD against P over the ten aggregate cells: geometric mean **{math.exp(sum(math.log(x) for x in dg) / len(dg)):.3f}**")

    # ---------------- ttft ----------------
    tt = {key: ttft(run) if run else {} for key, run in where.items()}
    print("\n## Cold TTFT, s (median of 2 reps, idle; 1k is the harness control cell)\n")
    print("| case | " + " | ".join(str(c) for c in levels) + " |")
    print("|---|" + "---|" * len(levels))
    for case in TTFT_ORDER:
        for arm in ("P", "D"):
            row = [f"{case} {arm}"]
            for c in levels:
                cell = tt[(arm, c)].get(case, {})
                suffix = f" (n{cell.get('n')},x{cell.get('excluded')})" if cell.get("excluded") else ""
                row.append(f(cell.get("med"), 3) + suffix)
            print("| " + " | ".join(row) + " |")
        row = [f"{case} D/P"]
        for c in levels:
            pm, dm = tt[("P", c)].get(case, {}).get("med"), tt[("D", c)].get(case, {}).get("med")
            row.append(f(ratio(dm, pm), 3))
        print("| " + " | ".join(row) + " |")
    print()
    print("Against the doc (idle column): P/doc and D/doc.\n")
    print("| case | " + " | ".join(f"{c} P/D" for c in levels) + " |")
    print("|---|" + "---|" * len(levels))
    for case in ("cold8k-off", "cold8k-on", "cold32k-off", "cold32k-on", "cold1k-off"):
        refs = doc["ttft_idle"].get(case, [])
        row = [case]
        for i, c in enumerate(levels):
            ref = refs[doc_levels.index(c)] if c in doc_levels and doc_levels.index(c) < len(refs) else None
            row.append(f"{f(ratio(tt[('P', c)].get(case, {}).get('med'), ref), 3)} / "
                       f"{f(ratio(tt[('D', c)].get(case, {}).get('med'), ref), 3)}")
        print("| " + " | ".join(row) + " |")

    # ---------------- warm ----------------
    print("\n## Warm agent turn: a kept 100k conversation plus 2k new tokens, idle\n")
    print("| concurrency | P med s (n, cached) | D med s (n, cached) | D/P | doc |")
    print("|---:|---|---|---:|---:|")
    for c in levels:
        row = [str(c)]
        for arm in ("P", "D"):
            cell = tt[(arm, c)].get("warm2k", {})
            good = [s for s in cell.get("samples", []) if not s["flagged"]]
            cached = ",".join(str(s["cached"]) for s in good) or "-"
            prompts = ",".join(str(s["prompt"]) for s in good) or "-"
            row.append(f"{f(cell.get('med'), 3)} (n{cell.get('n')}, x{cell.get('excluded')}, "
                       f"cached {cached} of prompt {prompts})")
        pm, dm = tt[("P", c)].get("warm2k", {}).get("med"), tt[("D", c)].get("warm2k", {}).get("med")
        ref = doc["ttft_idle"]["warm2k"][doc_levels.index(c)] if c in doc_levels else None
        print(f"| {row[0]} | {row[1]} | {row[2]} | {f(ratio(dm, pm), 3)} | {f(ref, 3)} |")

    # ---------------- boot ----------------
    print("\n## Boot, memory and golden\n")
    print("| concurrency | arm | boot s | sequence memory | golden | image |")
    print("|---:|---|---:|---|---|---|")
    for c in levels:
        for arm in ("P", "D"):
            run = where[(arm, c)]
            m = meta(run) if run else {}
            seq = m.get("plan_seqmem", "-").replace("sequence memory: ", "")
            gold = m.get("gold", "-").split(" identical")[0]
            print(f"| {c} | {arm} | {m.get('boot_s', '-')} | {seq} | {gold} | "
                  f"`{(m.get('image_tag', '-')).split(':')[-1]}` `{m.get('image_id', '')[:14]}` |")
    for c in levels:
        if c in doc_levels:
            i = doc_levels.index(c)
            print(f"| {c} | doc | {doc['boot_s'][i]} | {doc['boot_seqmem_gib'][i]:.2f} GiB | 6/6 | - |")

    print("\n## Thermals and traffic (GB10: clocks sag with sustained load, so every probe window's reading is kept)\n")
    print("| concurrency | arm | at boot | after golden | after decode | after TTFT | foreign request lines |")
    print("|---:|---|---|---|---|---|---:|")
    for c in levels:
        for arm in ("P", "D"):
            run = where[(arm, c)]
            m = meta(run) if run else {}
            row = [str(c), arm]
            for key in ("gpu_boot_start", "gpu_gold", "gpu_dec", "gpu_ttft"):
                row.append(m.get(key, "-").replace("gpu_after ", "").replace("gpu ", "").rstrip(";"))
            row.append(m.get("foreign_lines", "-"))
            print("| " + " | ".join(row) + " |")

    # ---------------- boot to boot ----------------
    def run_n(root: str, arm: str, c: int, n: int) -> str | None:
        path = os.path.join(root, arm, f"c{c}", f"run{n}")
        return path if os.path.isdir(path) else None

    both = [(arm, c) for arm in ("P", "D") for c in levels if run_n(args.root, arm, c, 2)]
    if both:
        print("\n## Boot to boot: the first boot against its rerun (the rule's second pass)\n")
        print("| concurrency | arm | prose run1 | prose run2 | delta | code run1 | code run2 | delta | 8k run1 | 8k run2 |")
        print("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for arm, c in both:
            r1, r2 = dec(run_n(args.root, arm, c, 1)), dec(run_n(args.root, arm, c, 2))
            t1, t2 = ttft(run_n(args.root, arm, c, 1)), ttft(run_n(args.root, arm, c, 2))
            cells_row = [str(c), arm]
            for kind in ("prose", "code"):
                a, b = med(r1.get(kind, {}).get("agg")), med(r2.get(kind, {}).get("agg"))
                cells_row += [f(a), f(b), f(ratio(b, a), 3)]
            cells_row += [f(t1.get("cold8k-off", {}).get("med"), 3), f(t2.get("cold8k-off", {}).get("med"), 3)]
            print("| " + " | ".join(cells_row) + " |")

    # ---------------- token hashes ----------------
    print("\n## Token hashes every cell: P against D at the same prompt (kind, pass, j)\n")
    print("| concurrency | kind | rows | text sha equal | engine token_sha equal | P token shas | D token shas |")
    print("|---:|---|---:|---:|---:|---:|---:|")
    for c in levels:
        hp, hd = hashes(where[("P", c)]) if where[("P", c)] else {}, hashes(where[("D", c)]) if where[("D", c)] else {}
        for kind in ("prose", "code"):
            keys = [k for k in hp if k[0] == kind and k in hd]
            text_eq = sum(1 for k in keys if hp[k].get("sha") == hd[k].get("sha"))
            tok_eq = sum(1 for k in keys if hp[k].get("token_sha") and hp[k].get("token_sha") == hd[k].get("token_sha"))
            print(f"| {c} | {kind} | {len(keys)} | {text_eq} | {tok_eq} | "
                  f"{len({hp[k].get('token_sha') for k in keys if hp[k].get('token_sha')})} | "
                  f"{len({hd[k].get('token_sha') for k in keys if hd[k].get('token_sha')})} |")

    # ---------------- not taken ----------------
    print("\n## Cells not taken in this window\n")
    print("- the doc's under-load TTFT bracket (`load<C-1>`) at every level: idle only here")
    print("- the doc's 120k TTFT cases and its 1k thinking-on cell; 1k thinking-off is the control here")
    print("- RigMark: not run in this window")
    print("- the doc's 512-token cells are reproduced; no 256-token or short-prompt cells are reported")
    return 0


if __name__ == "__main__":
    sys.exit(main())
