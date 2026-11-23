#!/usr/bin/env python3
"""Fail when prod.env and the live production container disagree on a serve setting.

prod.env is a hand copy of the production launcher's environment (`docker inspect` of the production
container), and a hand copy drifts: it went from 52 to 54 settings between the 2026-11-20 and 2026-11-23
captures with nothing comparing it to the container. This gate reads the container's own `Config.Env` and
compares every `TF_*` / `TENSORFOLD_*` name against the copy, in both directions:

  DIFF       the name is in both and the values differ
  MISSING    prod.env states it and the container does not carry it
  EXTRA      the container carries it and prod.env does not state it
  DUPLICATE  prod.env states one name twice, so the last line silently wins
  NO-VALUE   prod.env has a bare `export NAME`, which says nothing about the container
  PRESENT    prod.env says `unset NAME` and the container carries it

Run it on the box, beside the serve, after any production restart or restore:

  python scripts/qwen38/zig/target/env/check-prod-env.py
  python scripts/qwen38/zig/target/env/check-prod-env.py --container qwen38-flash-next-tf
  python scripts/qwen38/zig/target/env/check-prod-env.py --inspect /tmp/prod-inspect.json

`--inspect FILE` takes a saved `docker inspect <container>` (the JSON array of objects) or the output of
`docker inspect <container> --format '{{json .Config.Env}}'` (a JSON array of `NAME=value` strings), so the
gate can be dry-run without the box. Exit 0 when the copy equals the live environment, 1 on any difference,
2 on an unreadable input.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXPORT = re.compile(r'^export ([A-Z0-9_]+)=(.*)$')
BARE = re.compile(r'^export ([A-Z0-9_]+)\s*$')
UNSET = re.compile(r'^unset ([A-Z0-9_]+)$')


def prod_settings(path):
    """Read prod.env: name -> ('value', text) or ('unset', None); plus the file's own defects."""
    values, problems = {}, []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = EXPORT.match(line)
        if m:
            name, value = m.group(1), m.group(2)
            if name in values:
                problems.append(f"DUPLICATE {name}: prod.env line {lineno} states it again; the last line wins")
            values[name] = ("value", value)
            continue
        m = BARE.match(line)
        if m:
            problems.append(f"NO-VALUE {m.group(1)}: a bare `export` says nothing about the container; state "
                            f"the value or `unset` the name")
            continue
        m = UNSET.match(line)
        if m:
            values[m.group(1)] = ("unset", None)
            continue
        problems.append(f"UNPARSED line {lineno}: {line[:80]}")
    return values, problems


def container_env(args):
    if args.inspect:
        data = json.loads(Path(args.inspect).read_text(encoding="utf-8"))
    else:
        cmd = ["docker", "inspect", args.container, "--format", "{{json .Config.Env}}"]
        try:
            data = json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            raise SystemExit(f"check-prod-env: cannot read {args.container}'s environment: {e}")
    if isinstance(data, dict):
        data = data.get("Config", {}).get("Env", [])
    elif isinstance(data, list) and data and isinstance(data[0], dict):
        data = data[0].get("Config", {}).get("Env", [])
    env = {}
    for item in data:
        name, _, value = item.partition("=")
        env[name] = value
    return env


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prod", default=str(HERE / "prod.env"), help="the hand copy of the production env")
    ap.add_argument("--container", default="qwen38-flash-next-tf", help="the production container")
    ap.add_argument("--inspect", help="a saved docker inspect JSON, or the --format '{{json .Config.Env}}' array")
    ap.add_argument("--prefix", default="^(TENSORFOLD|TF_)", help="the names the launcher passes and the engine reads")
    ap.add_argument("--skip", default="TENSORFOLD_API_KEY", help="comma list of names never compared")
    args = ap.parse_args()

    prod_path = Path(args.prod)
    if not prod_path.is_file():
        print(f"check-prod-env: {prod_path} does not exist", file=sys.stderr)
        return 2
    values, problems = prod_settings(prod_path)
    live = container_env(args)
    prefix = re.compile(args.prefix)
    skip = {s.strip() for s in args.skip.split(",") if s.strip()}

    stated = {n: v for n, v in values.items() if prefix.search(n) and n not in skip}
    carried = {n: v for n, v in live.items() if prefix.search(n) and n not in skip}
    for name in sorted(stated):
        kind, value = stated[name]
        if name not in carried:
            if kind == "value":
                problems.append(f"MISSING {name}: prod.env states {value!r} and the container does not carry it")
            continue
        if kind == "unset":
            problems.append(f"PRESENT {name}: prod.env says unset and the container carries {carried[name]!r}")
        elif carried[name] != value:
            problems.append(f"DIFF {name}: prod.env {value!r} against container {carried[name]!r}")
    for name in sorted(set(carried) - set(stated)):
        problems.append(f"EXTRA {name}={carried[name]!r}: the container carries it and prod.env does not state it")

    equal = sum(1 for n in stated if stated[n][0] == "value" and carried.get(n) == stated[n][1])
    absent = sum(1 for n in stated if stated[n][0] == "unset" and n not in carried)
    for p in problems:
        print(p)
    print(f"prod-env: {len(stated)} settings in prod.env ({len(stated) - absent} stated, {absent} unset), "
          f"{len(carried)} in the container, {equal} equal, {len(problems)} problem(s)")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
