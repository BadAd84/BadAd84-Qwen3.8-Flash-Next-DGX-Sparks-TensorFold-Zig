#!/usr/bin/env python3
"""check_env.py ARMENV CONTAINER_ENV [--allow-extra NAME]...: prove the boot's environment is the arm's.

ARMENV is the arm's own env file (the materialised screen base, or that base with one line changed);
CONTAINER_ENV is `docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}'` of the running container.

Every `export NAME=value` must be in the container at that value.
Every `unset NAME`, and every `export NAME` with no value, must be ABSENT: both state that the setting's
truth is the variable's absence, and a valueless export is not absence (it leaves an inherited value alone).
Every serve name in the container that the arm does not state is EXTRA and a failure: the boot is then
running a setting the env of record does not state, and the boot is not the arm it claims to be. The only
exceptions are names declared with --allow-extra, one flag a name: the recipe launcher's own config.sh
defaults and the image ENV, which are measured and recorded rather than inferred. EXTRA is not advisory; a
new name in either source is a new setting and fails until it is declared or written in the env.

Prints one line a mismatch, then `EXTRA-N n` and `SETTINGS-OK <stated>` or `SETTINGS-BAD <n>`. Exit 1 on
any failure.
"""
import argparse
import re
import sys
from pathlib import Path

SERVE = re.compile(r"^(TF_|TENSORFOLD_)[A-Z0-9_]+$")


def read_arm(path):
    value, absent = {}, set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("unset "):
            absent.add(line[len("unset "):].strip())
            continue
        if not line.startswith("export "):
            continue
        body = line[len("export "):].strip()
        if "=" not in body:
            absent.add(body)
            continue
        name, _, val = body.partition("=")
        value[name] = val
    return value, absent


def read_container(path):
    have = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        name, sep, val = raw.partition("=")
        if sep and SERVE.match(name.strip()):
            have[name.strip()] = val
    return have


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("armenv")
    ap.add_argument("container_env")
    ap.add_argument("--allow-extra", action="append", default=[],
                    help="a serve name the launcher or image supplies on every boot; repeatable")
    args = ap.parse_args()
    value, absent = read_arm(Path(args.armenv))
    have = read_container(Path(args.container_env))
    allow = set(args.allow_extra)

    bad = []
    for name, want in sorted(value.items()):
        if name not in have:
            bad.append(f"ABSENT {name}={want}")
        elif have[name] != want:
            bad.append(f"VALUE {name}={have[name]} want {want}")
    for name in sorted(absent):
        if name in have:
            bad.append(f"PRESENT {name}={have[name]} want unset")
    extra = sorted(set(have) - set(value) - absent - allow)
    for name in extra:
        bad.append(f"EXTRA {name}={have[name]}")

    for b in bad:
        print(b)
    print(f"EXTRA-N {len(extra)}")
    print(f"SETTINGS-OK {len(value)}" if not bad else f"SETTINGS-BAD {len(bad)}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
