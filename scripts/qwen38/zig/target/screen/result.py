#!/usr/bin/env python3
"""result.py --box DIR [--plan FILE]: compose RESULT.md from a finished (or partial) screen window.

Reads what the window wrote: plan.tsv, out/scores.tsv, out/table.md, every out/<plan arm>/<role>/meta.json,
out/ref.txt, out/base-filter.txt, out/base-not-carried.txt, out/LEFT, out/production.txt, out/gate-marker.txt,
out/run.log. Writes out/RESULT.md. Never invents a number: a missing file is printed as absent, and the
discarded warm-up boot is never counted as a boot of the window.
"""
import argparse
import json
import re
from datetime import datetime
from pathlib import Path

CELL_ORDER = ["d1-prose", "d1-code", "d4-prose", "d4-code", "d4-sampled", "c2k", "c32k"]


def read(path, default=""):
    p = Path(path)
    return p.read_text(encoding="utf-8", errors="replace") if p.is_file() else default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--box", required=True)
    ap.add_argument("--plan")
    a = ap.parse_args()
    box = Path(a.box)
    out = box / "out"
    plan_p = Path(a.plan) if a.plan else box / "plan.tsv"
    plan = []
    for line in read(plan_p).splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        arm, name, value, tier, why = line.split("\t")
        plan.append((arm, name, value, tier, why))

    scores = {}
    for line in read(out / "scores.tsv").splitlines()[1:]:
        f = line.split("\t")
        if len(f) >= 6:
            scores[f[0]] = {"verdict": f[3], "note": f[4], "cells": f[5:]}
    boots = []
    for arm, _, _, _, _ in plan:
        for role in ("c1", "a", "a2", "c2"):
            m = out / arm / role / "meta.json"
            if m.is_file():
                boots.append((arm, role, json.loads(read(m))))
    wall = None
    log = read(out / "run.log")
    starts = re.findall(r"^(\S+) ARM-START", log, re.M)
    dones = re.findall(r"^(\S+) ARM-DONE", log, re.M)
    if starts and dones:
        wall = (datetime.fromisoformat(dones[-1]) - datetime.fromisoformat(starts[0])).total_seconds()
    held = re.search(r"^(\S+) HELD", log, re.M)
    done = re.search(r"^(\S+) DONE", log, re.M)

    counts = {}
    for s in scores.values():
        counts[s["verdict"]] = counts.get(s["verdict"], 0) + 1

    L = []
    add = L.append
    add(f"# The knob screen, measured: {len(plan)} candidates, control against candidate against control\n")
    add(f"Lane KnobScreen, spark6. Window started {held.group(1) if held else 'not recorded'} and ended "
        f"{done.group(1) if done else 'not finished'}. "
        f"Arms started {len(starts)}, arms completed {len(dones)}, boot records {len(boots)}. "
        f"Wall clock from first ARM-START to last ARM-DONE: "
        f"{f'{wall / 3600:.2f} h' if wall is not None else 'not recorded'}.\n")
    add("The rule is `scripts/qwen38/zig/target/screen/RULE.md`, written before the first row. A screen is "
        "never a verdict: a PROMOTE only earns the five-level A/B later, and nothing here is written into "
        "`dev.env`.\n")

    gate = read(out / "gate-marker.txt").strip()
    add("## The gate\n")
    add("EnvBoot's fast r5 prompt-following verdict, read before any boot:\n")
    add("```\n" + (gate if gate else "no marker on disk") + "\n```\n")

    add("## The base the screen booted\n")
    add("The driver copies the committed `scripts/qwen38/zig/target/env/dev.env` at start and records its "
        "sha256; the base is that file as the recipe launcher's own name filter can carry it. Lines the "
        "filter cannot carry are commented in the base and listed in `out/base-not-carried.txt`: they are "
        "absent from the container on every boot of this window, so no arm sets one and no verdict reads one.\n")
    add("```\n" + read(out / "ref.txt", "no ref.txt").strip() + "\n"
        + read(out / "base-filter.txt", "no base-filter.txt").strip().splitlines()[0]
        + "\n```\n")
    not_carried = read(out / "base-not-carried.txt").strip()
    add("Not carried by the launcher, so not measured (name, value, line):\n")
    add("```\n" + (not_carried if not_carried else "none") + "\n```\n")

    add("## The table\n")
    add("One row an arm. `c1` and `c2` are the two control boots, `arm` the candidate; the numbers are the "
        "first treatment cell (`d4-prose`, or `d4-sampled` for `SAMPLED_HEADS`). `pair` is this arm's own "
        "control-to-control spread, `pool` the median over every control pair in the window, which is the "
        "margin every test uses (floored at 1 percent). The verdict and its note are the analyzer's, by the "
        "rule's precedence.\n")
    add(read(out / "table.md", "no table.md: the analyzer did not run") + "\n")

    add("## Every cell\n")
    add("Each cell as `arm value (change against the control mean, this arm's pair spread, the pooled spread)`. "
        "Throughput cells are tok/s (higher better); `c2k` and `c32k` are TTFT seconds (lower better).\n")
    add("| arm | setting | " + " | ".join(CELL_ORDER) + " | verdict |")
    add("|---|---|" + "---|" * len(CELL_ORDER) + "---|")
    for arm, name, value, tier, why in plan:
        s = scores.get(arm)
        if not s:
            add(f"| {arm} | {name}={value} | " + " | ".join([""] * len(CELL_ORDER)) + " | not run |")
            continue
        add(f"| {arm} | {name}={value} | " + " | ".join(s["cells"]) + f" | {s['verdict']} |")
    add("")
    add("Counts: " + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) if counts else "none") + "\n")

    if boots:
        add("## Boots\n")
        add("| arm | boot | rc | health | wall s | settings ok | foreign | gpu after |")
        add("|---|---|---:|---:|---:|---:|---:|---|")
        for arm, role, d in boots:
            add(f"| {arm} | {role} | {d.get('boot_rc')} | {d.get('health')} | {d.get('boot_wall_s')} | "
                f"{d.get('settings_ok')} | {d.get('foreign')} | {d.get('temp')} |")
        add("")
    warm = read(out / "warmup" / "w" / "meta.json")
    add("The window's first boot is a discarded warm-up: it proves the serve shape and takes the first-boot "
        "penalty, and no verdict reads its cells"
        + (f" (boot record rc {json.loads(warm).get('boot_rc')}, health {json.loads(warm).get('health')}).\n"
           if warm else "; its boot record is absent.\n"))

    add("## What the cap left out\n")
    left = read(out / "LEFT").strip()
    left_n = len([line for line in left.splitlines() if line.strip()])
    add(f"The {left_n} settings below rank after the {len(plan)} screened, by `docs/KNOB-COVERAGE.md`'s "
        "order. None was booted, measured or changed in this window. The A4 group is cache and resume tuning "
        "and this window's cells cannot judge it at all (they need a resume or two interleaved "
        "conversations).\n")
    add("- `TF_FLASHNEXT_TABLE_WARM` (A3): PLE table read ahead after load, cold TTFT and boot wall.\n"
        "- `TENSORFOLD_CUDA_KERNELS` (A3): captured kernel set against native, decode 1/4/8 and cold 1k/8k/32k.\n"
        "- `TENSORFOLD_PREFIX_WAIT_MS` (A4): TTFT on a shared-prefix turn.\n"
        "- `TENSORFOLD_PROMPT_CACHE_KEEP_OTHERS` (A4): two interleaved conversations, later-turn TTFT.\n"
        "- `TF_PROMPT_INTERMEDIATE` (A4): long agent turn, resume TTFT.\n"
        "- `TENSORFOLD_RESTORE_PREFETCH`, `_GIB`, `_MS` (A4): under the disk tier, resume TTFT.\n")
    if left:
        add("Recorded skips:\n```\n" + left + "\n```\n")

    add("## The end state\n")
    add("```\n" + (read(out / "production.txt").strip() or "production.txt absent") + "\n```\n")
    before = read(out / "prod-before.txt").strip()
    add("Production at window start: `" + (before or "not recorded") + "`. "
        + ("The guard found it serving, so the restore above is the first transition of that container.\n"
           if before.startswith("found-up") else
           "The guard brought production up itself, so the window began from a production this driver started "
           "and the restore above is the second transition of that same container; a /health gap before the "
           "window belongs to whatever stopped it, and the gap after it belongs to the arms.\n"
           if before.startswith("started-by-guard") else
           "No start state was recorded, which is itself a gap in the audit.\n"))
    add("Nothing was promoted: no line of `dev.env` was changed by this window, and every arm env is a copy "
        "under `work/KnobScreen/env/`.\n")

    add("## What stage two inherits\n")
    add("A KILL here needs a treatment cell worse than both controls beyond the pooled margin and either a "
        "second judged cell lost in the same boot or a second candidate boot that loses the same cell. A "
        "single-cell, single-boot loss is reported `KILL-PENDING`, not as a verdict, and its alternative value "
        "stays on the worklist.\n")
    add("The margins are pooled over every control pair in the window, so a window of few arms has a wider "
        "margin on the same cells than a long one, and a pair more than 25 percent apart makes only its own "
        "arm inconclusive.\n")
    add("A PROMOTE here is a lead, not a setting: it earns the full five-level interleaved A/B (one fresh boot "
        "a level, 1, 2, 4, 6 and 8 streams) with the same prompts and seeds, plus the per-setting cold cells "
        "`docs/KNOB-COVERAGE.md` names for that setting. A KILL removes the alternative value and records the "
        "losing cell. An INCONCLUSIVE is either a spread too wide for the cell to resolve (stage two needs a "
        "quieter box or more reps) or a treatment cell that moved inside the noise; in both cases the setting "
        "stays on the unmeasured list and is not promoted on a hunch.\n")

    (out / "RESULT.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"wrote {out / 'RESULT.md'}")


if __name__ == "__main__":
    main()
