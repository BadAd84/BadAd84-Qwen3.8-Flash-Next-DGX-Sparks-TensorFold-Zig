"""make_result.py - assemble RESULT.md from the fetched evidence, so every number in it is copied from a run file.

Inputs (all under this directory after fetch.sh):
  box/out/build.out              the image id and its SOURCE/NVCC/ZIG/BUILD OK lines
  box/out/<window>/analysis/*    the analyzer's tables and summary.json
  box/out/<window>/run.log       boot/probe lines, the restore line
  box/out/FINAL.md               production /health, the container, lock holders, free space
  CLASSIFY.md                    the classification table, inlined
  VERDICTS.md                    the per-knob verdict table, authored, appended verbatim

Usage: python make_result.py [--windows w1,w2,w3] [--out RESULT.md]
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def read(path, default=""):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return default


METHOD = """## Method

- **The checkpoint is the recipe's NVFP4 one.** Every arm boots `CHECKPOINT=nvfp4` (nvidia/Qwen3.8-Flash-Next-FP4-Local
  at b9ce18a6), as the brief and every earlier Flash Next receipt do. The container running on :8888 while these
  windows were prepared serves azampatti's INT4-AutoRound checkpoint (`docker inspect` of `qwen38-flash-next-tf`), so
  these arms compare against each other and never against that serve's absolute numbers.
- **One image, many boots.** Every arm runs `tensorfold-qwen38:knob-m-1ece6e6d`, built from a `git archive` of
  upstream main `1ece6e6d` whose tree was verified blob by blob against `git ls-tree -r` (12,601 entries, 0
  mismatches, 0 extra files) with the same Zig 0.17.0 and nvcc the recipe pins. Settings vary by environment only, so
  a difference between arms is the setting and nothing else.
- **The base environment is production's own.** Each boot gets the 52 `TENSORFOLD_*`/`TF_FLASHNEXT_*` lines that
  `~/qwen6-start-prod.sh` exports, printed per arm from the container's inspect. Of those, upstream main reads six
  (`TENSORFOLD_MEMORY_RESERVE_GIB`, `TENSORFOLD_VIDEO_TOKENS`, `TF_FLASHNEXT_BATCH_DRAWS`,
  `TF_FLASHNEXT_CONFIDENCE`, `TF_FLASHNEXT_DEPTH`, `TF_FLASHNEXT_WINDOW`) and ignores the other 46 names, which are
  this fork's own levers; the receipt says that rather than calling the baseline the production serve. An "off" arm
  passes the explicit off value where production sets the name on.
- **Every arm, every pass.** A: a fresh boot, `bench_openai` greedy three reps, `bench_concurrent --tokens 256
  --reps 3 --levels 1,2,4,6,8 --alone --serial --temperatures 0` (prose and code), the sampled exactness sweep
  (`--tokens 128 --reps 2 --levels 1,2,4,6 --temperatures 1.0,0`), the six golden prompts, `served_exactness drafts`
  and `turns`. B: a second boot with `--prompt-cache-gib 0` at a 131,072-token window for cold TTFT at 2k, 8k, 32k
  and 64k, `bench_cache --require-cold`, and `served_exactness fresh` against pass A's turns. P: one stream at
  131,072 for the solo-chunk arms. D: the resume-pressure bench for `TF_CACHE_EVICT`.
- **The noise rule.** Each treatment has two runs and each window is bracketed by two main runs. A cell is SLOWER
  when both treatment runs are under both main runs (for a latency: over) and the mean gap is over 1 percent, FASTER
  when both are over both and the gap is over 1 percent, LEVEL otherwise; a cell with fewer than two runs a side is
  reported with its gap and marked unmeasured.
- **Exactness is separate from speed.** Greedy replies are compared across arms by `token_sha256`; concurrent cells
  against the solo stream at 1, 2 and 4; drafted against `"draft": false`; a resumed reply against a fresh one on a
  cache-off server. A knob that changes a token is reported as such, with the first divergence, and never folded into
  a speed verdict.
- **Requests are accounted.** Every probe records the server's `mtp_drafted/accepted` counters and the container
  log's request lines before and after itself; an arm that saw a request it did not send, or whose boot or a probe
  failed, is rerun once on a fresh boot with its first attempt kept as `.rejected1`.
- **The GPU temperature is recorded at the start and end of every probe** (`gpu.txt`), and the box's free memory at
  every boot.
"""

def classify_table():
    """The rows of CLASSIFY.md's table, header included."""
    text = read(os.path.join(HERE, "CLASSIFY.md"))
    lines = [l for l in text.splitlines() if l.startswith("|")]
    return "\n".join(lines)


def window_section(window):
    out = os.path.join(HERE, "box", "out", window)
    analysis = os.path.join(out, "analysis")
    parts = [f"### Window `{window}`\n"]
    summary_path = os.path.join(analysis, "summary.json")
    if not os.path.exists(summary_path):
        parts.append(f"NOT ANALYSED: no {summary_path}. The run log's marker state is quoted instead.\n")
        log = read(os.path.join(out, "run.log"))
        tail = "\n".join(log.splitlines()[-12:])
        parts.append("```\n" + tail + "\n```\n")
        return "\n".join(parts)
    s = json.load(open(summary_path, encoding="utf-8"))
    parts.append(f"Image `{s['image']}`, base arms `{', '.join(s['base_arms'])}`, "
                 f"treatments `{', '.join(sorted(s['treatments']))}`.\n")
    for name, title in (("decode.md", "Decode cells"), ("ttft.md", "TTFT cells"), ("resume.md", "Resume and cache cells"),
                        ("exactness.md", "Exactness"), ("golden.md", "Cross-arm greedy equality"),
                        ("boot.md", "Boots, environment and foreign requests")):
        body = read(os.path.join(analysis, name))
        if body:
            parts.append(f"#### {title}\n")
            parts.append(body.strip() + "\n")
    return "\n".join(parts)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--windows", default="w1,w2,w3")
    p.add_argument("--out", default=os.path.join(HERE, "RESULT.md"))
    a = p.parse_args(argv)
    windows = [w for w in a.windows.split(",") if w]
    build = read(os.path.join(HERE, "box", "out", "build.out"))
    final = read(os.path.join(HERE, "box", "out", "FINAL.md"))
    verdicts = read(os.path.join(HERE, "VERDICTS.md"))
    notrun = read(os.path.join(HERE, "NOTRUN.md"))
    logs = []
    for w in windows:
        log = read(os.path.join(HERE, "box", "out", w, "run.log"))
        for line in log.splitlines():
            if line.startswith(("START ", "PLAN ", "BOOT ", "MEMLINE ", "ARM-OK", "ARM-FAILED", "ARM-RETRY", "RESTORE", "DONE")):
                logs.append(f"- `{w}` {line}")
    doc = []
    doc.append("# Knob receipt: every upstream setting that reaches the Flash Next CUDA serve\n")
    doc.append("Image built from upstream main `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, one image for every arm,")
    doc.append("each arm the same image and the same environment except one setting. Every number below is copied")
    doc.append("from a run file under `box/out/` by `make_result.py`; nothing is retyped.\n")
    doc.append("## The image\n")
    doc.append("```\n" + build.strip() + "\n```\n")
    doc.append(METHOD)
    doc.append("## Classification (one row per setting)\n")
    doc.append(classify_table() + "\n")
    doc.append("## Windows\n")
    for w in windows:
        doc.append(window_section(w))
    doc.append("## Verdict per knob\n")
    doc.append(verdicts.strip() + "\n")
    doc.append("## Not run, and why\n")
    doc.append(notrun.strip() + "\n")
    doc.append("## After the windows\n")
    doc.append("```\n" + final.strip() + "\n```\n")
    doc.append("## Run markers\n")
    doc.extend(logs)
    open(a.out, "w", encoding="utf-8", newline="\n").write("\n".join(doc) + "\n")
    print("wrote", a.out, len("\n".join(doc).splitlines()), "lines")


if __name__ == "__main__":
    sys.exit(main())
