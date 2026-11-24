#!/usr/bin/env python3
"""Check the register against dev.env: one verdict a row, every evidence path exists, every cited line lands.

The acceptance gate is two sentences: 0 verdicts with a missing evidence path, and 0 names with two verdicts.
Beyond that this opens every path a verdict names and, where the verdict cites `path:line`, reads that line and
requires it to contain the setting or a read call. The register's older lines cite a file without a line number;
they are counted as info, never as a failure.
"""
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]
DEV = REPO / "scripts/qwen38/zig/target/env/dev.env"
REG = REPO / "scripts/qwen38/zig/target/env/register.env"

KINDS = r"(default-ok|debt|unreachable|measured|inert|raw|launcher|absent|candidate|retired)"
VERDICT = re.compile(r"^#\s*" + KINDS + r"\s+([A-Z0-9_]+)\s*:\s*(.*)$")
PROD = re.compile(r"^#\s*prod\s+" + KINDS + r"\s+([A-Z0-9_]+)\s*:")
IMAGE_BAKED = re.compile(r"^#\s*image-baked\s+([A-Z0-9_]+)=")
PATH = re.compile(r"((?:work|docs|scripts|int-docs)/[A-Za-z0-9_./-]+)(?::(\d+))?")
READ = re.compile(r'(environment\.(read|value|path|parse|device)\(|getenv\(|rawText\(|profile\.(given|get|lookup)\()')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--register", default=str(REG))
    ap.add_argument("--dev", default=str(DEV))
    ap.add_argument("--baseline", default="", help="the register before the change, to prove the prod block intact")
    args = ap.parse_args()

    dev_rows = []
    for line in Path(args.dev).read_text(encoding="utf-8").splitlines():
        m = re.match(r"^(?:export|unset) ([A-Z0-9_]+)", line)
        if m:
            dev_rows.append(m.group(1))

    lines = Path(args.register).read_text(encoding="utf-8").splitlines()
    dev_v, prod_v, baked, problems, unlined = {}, {}, {}, [], []
    paths_opened = lines_read = 0
    for number, line in enumerate(lines, 1):
        pm = PROD.match(line)
        if pm:
            prod_v[pm.group(2)] = number
            continue
        b = IMAGE_BAKED.match(line)
        if b:
            baked[b.group(1)] = number
        m = VERDICT.match(line)
        if not m:
            continue
        kind, name, rest = m.groups()
        if name in dev_v:
            problems.append(f"TWO-VERDICTS {name}: lines {dev_v[name][1]} and {number}")
        dev_v[name] = (kind, number)
        tokens = PATH.findall(rest)
        if not tokens:
            problems.append(f"MISSING-EVIDENCE {name} (line {number}, {kind})")
            continue
        lined = False
        for path, at in tokens:
            paths_opened += 1
            p = REPO / path
            if not p.exists():
                problems.append(f"MISSING-PATH {name} (line {number}): {path}")
                continue
            if at:
                lined = True
                lines_read += 1
                body = p.read_text(encoding="utf-8", errors="replace").splitlines()
                if int(at) > len(body):
                    problems.append(f"LINE-PAST-END {name} (line {number}): {path}:{at} has {len(body)} lines")
                elif name not in body[int(at) - 1] and not READ.search(body[int(at) - 1]):
                    problems.append(f"LINE-WRONG {name} (line {number}): {path}:{at} names neither the setting "
                                    f"nor a read call")
        if not lined:
            unlined.append(f"{name} (line {number})")

    for name in (n for n in dev_rows if n not in dev_v):
        problems.append(f"UNVERDICTED {name}: dev.env states it and the register has no dev verdict")

    if args.baseline:
        base = [l for l in Path(args.baseline).read_text(encoding="utf-8").splitlines() if PROD.match(l)]
        new = [l for l in lines if PROD.match(l)]
        if base != new:
            problems.append(f"PROD-BLOCK-CHANGED: {len(base)} prod lines before, {len(new)} after")

    kinds = {}
    for kind, _ in dev_v.values():
        kinds[kind] = kinds.get(kind, 0) + 1
    print(f"register: {len(dev_rows)} dev rows, {len(dev_v)} dev verdicts, "
          f"{sum(1 for n in dev_rows if n in dev_v)} rows covered, "
          f"{sum(1 for n in dev_rows if n not in dev_v)} rows without, "
          f"{len(prod_v)} prod verdicts, {len(baked)} image-baked")
    print(f"register: kinds {', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))}")
    print(f"register: {paths_opened} evidence path(s) opened, {lines_read} cited line(s) read, "
          f"{len(unlined)} verdict(s) cite a file without a line number (the older style)")
    if args.baseline:
        print(f"register: prod block {len(prod_v)} lines "
              f"{'unchanged' if not any(p.startswith('PROD-BLOCK') for p in problems) else 'CHANGED'}")
    print(f"register-check: {len(problems)} problem(s)")
    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
