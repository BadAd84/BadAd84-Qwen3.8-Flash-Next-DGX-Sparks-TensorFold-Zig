#!/usr/bin/env python3
"""Which TF_/TENSORFOLD_ names an arm sets, and whether the image's served binary carries them.

The rule (PROMOTION-RULES.md, "Settings that no longer exist in the engine"): the served binary is the oracle for
the engine we actually run, so a name our environment sets that the binary lacks is either a package the image does
not carry or a row the engine dropped - both are reconciled before a cell is measured, and the finding is recorded.

  list       names an arm will set: export NAME= lines of an env file, assignment tokens of a launcher (its
             `exec env ...` block), and `${NAME:-...}` / `NAME=` defaults of the recipe's config.sh.
  from-env   names a running container carries (a NAME=value dump), plus a launcher and config.sh.
  check      compare a name list against the printable runs of the image's served binary.
  reconcile  names the container carries that the tested list lacks (a test-coverage hole, not a finding).

Usage:
  envnames.py list --dev-env in/dev.env --launcher ~/qwen6-start.sh --config ~/qwen-zig/scripts/config.sh \
      --exclude TF_REF,TF_REPO,TF_TAG,TF_RELEASE,TF_RELEASE_VERSION,TF_RELEASE_AARCH64_SHA256 --out names.txt
  envnames.py from-env --env live-env.txt --launcher ~/qwen6-start-prod.sh \
      --config ~/qwen-zig-prod/scripts/config.sh --out names-P.txt
  envnames.py check --names names.txt --strings strings.txt
  envnames.py reconcile --names names.txt --env container-env.txt
"""
from __future__ import annotations
import argparse
import re
import sys

NAME = re.compile(r"(?:^|[\s\"'({])((?:TF|TENSORFOLD)_[A-Z0-9_]+)(?==|:|\")")
EXPORT = re.compile(r"^export\s+([A-Z0-9_]+)=")
UNSET = re.compile(r"^unset\s+([A-Z0-9_]+)$")
ASSIGN = re.compile(r"^(?:export\s+)?((?:TF|TENSORFOLD)_[A-Z0-9_]+)=")
DEFAULT = re.compile(r"\$\{((?:TF|TENSORFOLD)_[A-Z0-9_]+):?-")
SETTING = re.compile(r"^(?:TF|TENSORFOLD)_[A-Z0-9_]+$")


def env_file_names(path: str) -> set[str]:
    names = set()
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for rx in (EXPORT, UNSET, ASSIGN):
            m = rx.match(line)
            if m:
                names.add(m[1])
    return names


def script_names(path: str) -> set[str]:
    """Assignment and ${NAME:-default} occurrences outside comments."""
    names = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.lstrip().startswith("#"):
            continue
        for rx in (ASSIGN, DEFAULT):
            for m in rx.finditer(line):
                names.add(m[1])
    return names


def env_dump_names(path: str) -> set[str]:
    names = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        name = line.strip().split("=", 1)[0]
        if SETTING.match(name):
            names.add(name)
    return names


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for cmd in ("list", "from-env"):
        p = sub.add_parser(cmd)
        if cmd == "from-env":
            p.add_argument("--env", required=True)
        else:
            p.add_argument("--dev-env", required=True)
        p.add_argument("--launcher", required=True)
        p.add_argument("--config", required=True)
        p.add_argument("--exclude", default="")
        p.add_argument("--out", required=True)
    p = sub.add_parser("check")
    p.add_argument("--names", required=True)
    p.add_argument("--strings", required=True)
    p = sub.add_parser("reconcile")
    p.add_argument("--names", required=True)
    p.add_argument("--env", required=True)
    args = ap.parse_args()

    if args.cmd in ("list", "from-env"):
        names = set()
        if args.cmd == "list":
            names |= env_file_names(args.dev_env)
        else:
            names |= env_dump_names(args.env)
        names |= script_names(args.launcher)
        names |= script_names(args.config)
        excluded = {n for n in args.exclude.split(",") if n}
        names -= excluded
        with open(args.out, "w", encoding="utf-8") as f:
            for name in sorted(names):
                f.write(name + "\n")
        print(f"names {len(names)} excluded {len(excluded)} -> {args.out}")
        return 0

    if args.cmd == "check":
        names = [n.strip() for n in open(args.names, encoding="utf-8") if n.strip()]
        carried = {line.strip() for line in open(args.strings, encoding="utf-8", errors="replace")}
        missing = [n for n in names if n not in carried]
        print(f"ENVSTR names {len(names)} carried {len(names) - len(missing)} missing {len(missing)}")
        for name in missing:
            print(f"ENVSTR-MISSING {name}")
        return 1 if missing else 0

    names = {n.strip() for n in open(args.names, encoding="utf-8") if n.strip()}
    extra = sorted(env_dump_names(args.env) - names)
    print(f"ENVRECON carried-not-tested {len(extra)}")
    for name in extra:
        print(f"ENVRECON-UNTESTED {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
