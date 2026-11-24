#!/usr/bin/env python3
"""Prove the launcher spark6 runs is the launcher this repo records.

The dev launcher is authored in this repo and copied to spark6 as `~/qwen6-start.sh`, so the same
file exists as two copies: the repo's and the box's. A boot from a stale copy measures another decode
path, which happened once already (the promotion rules name it). This gate compares the copies with
sha256 and fails on every drifted pair.

Two modes, both explicit - there is no default mode, because one of them reads a live box:

  --check-local   the repo's own copies of each launcher agree. The repo holds one file per launcher,
                  so the copies compared are the ones git records and the one a deployment is taken
                  from: the working-tree file, the index blob and the HEAD blob. A launcher edited in
                  the tree but not committed fails here, before the box comparison can bless it, and
                  an edit staged but not committed fails too.

  --check-box     the box's copies against the repo's, over ssh (BatchMode; the ambient ssh agent is
                  used and no credential is read here):
                    dev launcher        repo copy sha256 against the box's ~/qwen6-start.sh;
                    production launcher the box's ~/qwen6-start-prod.sh against the production
                                        branch's copy, and it must NOT equal the dev launcher, so a
                                        sync onto production cannot pass;
                    recipe filter       the environment-forwarding line in the recipe launcher the
                                        box runs (~/qwen-zig/start.sh) against the line this repo
                                        records verbatim at
                                        upstream/recipe-launcher-tf-env/0001-launcher-forward-tf-env.patch.
                  The recipe's copies of that line live on the box (the recipe tree and its
                  start-upstream.sh reference copy), so they are compared here and not locally; the
                  repo holds the line once, in that package, and check-launcher-contract.py reads the
                  filter from it.

Exit 0 clean, 1 with one line per drifted pair, 2 when the comparison could not be made (a launcher
is missing, git cannot read a copy, or ssh cannot reach the box). Every line names the two copies and
their shas, so a drift can be attributed without re-running anything.

  python scripts/qwen38/zig/target/env/check-launcher-sync.py --check-local
  python scripts/qwen38/zig/target/env/check-launcher-sync.py --check-box --host adam@spark6.ots-int.net
"""
import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]

# (label, repo path): every launcher the repo owns. The dev launcher's copy under $HOME on the box is
# QWEN6_BOX; the retired spark4 launcher has no box copy today (the repo's launcher table says so).
LAUNCHERS = (
    ("dev launcher", "scripts/qwen38/zig/qwen6-start.sh"),
    ("spark4 launcher", "scripts/qwen38/qwen-start.sh"),
)
QWEN6_BOX = "qwen6-start.sh"
PRODUCTION = ("production launcher", "production/qwen6-start-prod.sh", "qwen6-start-prod.sh")
RECORDED_FILTER = "upstream/recipe-launcher-tf-env/0001-launcher-forward-tf-env.patch"
REMOTE = (
    'sha256sum "$HOME/qwen6-start.sh" "$HOME/qwen6-start-prod.sh"; echo LAUNCHER-SYNC-MARK; '
    '''grep -n 'TENSORFOLD|TF_' "$HOME/qwen-zig/start.sh" | head -5'''
)


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return path.as_posix()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str | None:
    try:
        return sha(path.read_bytes())
    except OSError:
        return None


def git_sha(repo: Path, spec: str) -> str | None:
    try:
        r = subprocess.run(["git", "-C", str(repo), "show", spec],
                           capture_output=True, cwd=str(repo))
    except OSError:
        return None
    return sha(r.stdout) if r.returncode == 0 else None


def local(repo: Path) -> int:
    pairs = drifted = 0
    verdicts = []
    for label, rel in LAUNCHERS:
        path = repo / rel
        copies = {
            "working tree": file_sha(path),
            "index": git_sha(repo, f":{rel}"),
            "HEAD": git_sha(repo, f"HEAD:{rel}"),
        }
        missing = [name for name, value in copies.items() if value is None]
        if missing:
            drifted += 1
            verdicts.append(f"MISSING {label}: no {' or '.join(missing)} copy of {rel}")
            continue
        names = list(copies)
        found = 0
        for i, left in enumerate(names):
            for right in names[i + 1:]:
                pairs += 1
                if copies[left] != copies[right]:
                    found += 1
                    drifted += 1
                    verdicts.append(
                        f"DRIFT {label}: {left} {copies[left][:12]} != {right} {copies[right][:12]} ({rel})")
        if not found:
            verdicts.append(f"EQUAL {label}: working tree = index = HEAD {copies['HEAD'][:12]} ({rel})")
    for line in verdicts:
        print(line)
    print(f"launcher-sync: {len(LAUNCHERS)} launcher(s), {pairs} pair(s), {drifted} drifted")
    return 1 if drifted else 0


def recorded_filter(path: Path) -> tuple[str, int] | None:
    """The filter regex from the recorded deployed launcher line (a patch's + side, or a shell file)."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    patch = any(line.startswith(("+", "-")) for line in lines)
    found = []
    for number, line in enumerate(lines, start=1):
        if patch and not line.startswith("+"):
            continue
        for m in re.finditer(r"grep -E '([^']+)'", line):
            found.append((m.group(1), number))
    return found[0] if len(found) == 1 else None


def remote_reply(host: str) -> str | None:
    try:
        r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", host, REMOTE],
                           capture_output=True, text=True)
    except OSError as error:
        print(f"BOX-UNREACHABLE {host}: ssh could not start: {error}")
        return None
    if r.returncode != 0:
        detail = (r.stderr.strip().splitlines() or [f"exit {r.returncode}"])[-1]
        print(f"BOX-UNREACHABLE {host}: {detail}")
        return None
    return r.stdout


def box(repo: Path, recorded: Path, reply: str, source: str) -> int:
    head, _, tail = reply.partition("LAUNCHER-SYNC-MARK")
    shas = {}
    for line in head.splitlines():
        m = re.match(r"^([0-9a-f]{64})\s+(\S+)$", line.strip())
        if m:
            shas[Path(m.group(2)).name] = m.group(1)
    filter_line = filter_regex = None
    for line in tail.splitlines():
        m = re.match(r"^(\d+):(.*)$", line)
        if m and "grep -E" in m.group(2):
            inner = re.search(r"grep -E '([^']+)'", m.group(2))
            if inner:
                filter_line, filter_regex = int(m.group(1)), inner.group(1)
    if not shas:
        print(f"BOX-UNREADABLE {source}: no sha256sum line in the reply")
        return 2

    verdicts = []
    checks = drifted = 0
    dev_rel = LAUNCHERS[0][1]
    dev_sha = file_sha(repo / dev_rel)
    box_dev = shas.get(QWEN6_BOX)
    if dev_sha is None:
        print(f"MISSING dev launcher: {dev_rel} is not in {repo}")
        return 2
    if box_dev is None:
        print(f"MISSING dev launcher: {source} has no ~/{QWEN6_BOX}")
        return 2
    checks += 1
    if dev_sha == box_dev:
        verdicts.append(f"EQUAL dev launcher: repo {dev_sha[:12]} == {source}:~/{QWEN6_BOX} {box_dev[:12]}")
    else:
        drifted += 1
        verdicts.append(f"DRIFT dev launcher: repo {dev_sha[:12]} != {source}:~/{QWEN6_BOX} {box_dev[:12]}")

    _, prod_rel, prod_box = PRODUCTION
    box_prod = shas.get(prod_box)
    ref_prod = git_sha(repo, f"production:{prod_rel}")
    if box_prod is None:
        print(f"MISSING {PRODUCTION[0]}: {source} has no ~/{prod_box}")
        return 2
    checks += 1
    if box_prod != box_dev:
        verdicts.append(f"EQUAL {PRODUCTION[0]} distinct: {source} {box_prod[:12]} != dev launcher {box_dev[:12]}")
    else:
        drifted += 1
        verdicts.append(f"DRIFT {PRODUCTION[0]} overwritten: {source} {prod_box} equals the dev launcher's sha {box_dev[:12]}")
    if ref_prod is None:
        verdicts.append(f"INFO {PRODUCTION[0]}: no production branch in {repo}, compared by sha only")
    else:
        checks += 1
        if box_prod == ref_prod:
            verdicts.append(f"EQUAL {PRODUCTION[0]}: {source} {box_prod[:12]} == production:{prod_rel} {ref_prod[:12]}")
        else:
            drifted += 1
            verdicts.append(f"DRIFT {PRODUCTION[0]}: {source} {box_prod[:12]} != production:{prod_rel} {ref_prod[:12]}")

    record = recorded_filter(recorded)
    if record is None:
        print(f"NO-FILTER {recorded}: no single grep -E line to compare")
        return 2
    want, want_line = record
    record_label = rel(recorded)
    checks += 1
    if filter_regex is None:
        drifted += 1
        verdicts.append(f"DRIFT recipe filter: {source}:~/qwen-zig/start.sh carries no env-forwarding line, "
                        f"the record at {record_label}:{want_line} is {want}")
    elif filter_regex == want:
        verdicts.append(f"EQUAL recipe filter: {source}:~/qwen-zig/start.sh:{filter_line} == "
                        f"{record_label}:{want_line} {want}")
    else:
        drifted += 1
        verdicts.append(f"DRIFT recipe filter: {source}:~/qwen-zig/start.sh:{filter_line} carries {filter_regex}, "
                        f"the record at {record_label}:{want_line} is {want}")
    for line in verdicts:
        print(line)
    print(f"launcher-sync: {source}, {checks} check(s), {drifted} drifted")
    return 1 if drifted else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="sha256 the launcher copies against each other.")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check-local", action="store_true",
                      help="the repo's working-tree, index and HEAD copies of each launcher agree")
    mode.add_argument("--check-box", action="store_true",
                      help="the box's launcher copies against the repo's, over ssh")
    ap.add_argument("--host", default="adam@spark6.ots-int.net",
                    help="the box --check-box reads (default adam@spark6.ots-int.net)")
    ap.add_argument("--repo", default=str(REPO),
                    help="the repo whose launcher copies are compared (default: the repo this gate ships in)")
    ap.add_argument("--recorded-from", default=str(REPO / RECORDED_FILTER),
                    help=f"the recorded deployed launcher line (default: {RECORDED_FILTER})")
    ap.add_argument("--from-file", default="",
                    help="with --check-box: re-read a saved probe reply instead of running ssh "
                         "(the format --print-remote produces)")
    ap.add_argument("--print-remote", action="store_true",
                    help="with --check-box: print the probe script the box side runs, for a saved receipt")
    args = ap.parse_args()
    repo = Path(args.repo).resolve()
    if args.check_local:
        if args.from_file or args.print_remote:
            ap.error("--from-file and --print-remote belong to --check-box")
        return local(repo)
    if args.print_remote:
        print(REMOTE)
        return 0
    if args.from_file:
        try:
            reply = Path(args.from_file).read_text(encoding="utf-8")
        except OSError as error:
            print(f"NO-RECEIPT {args.from_file}: {error}")
            return 2
        source = f"receipt {Path(args.from_file).name}"
    else:
        reply = remote_reply(args.host)
        if reply is None:
            return 2
        source = f"host {args.host}"
    return box(repo, Path(args.recorded_from), reply, source)


if __name__ == "__main__":
    sys.exit(main())
