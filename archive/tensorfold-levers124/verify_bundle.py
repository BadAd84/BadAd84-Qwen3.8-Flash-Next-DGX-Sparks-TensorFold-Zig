#!/usr/bin/env python3
"""verify_bundle.py BUNDLE UPSTREAM_CLONE [REFS.txt] - prove a bundle restores every ref it lists.

Makes a throwaway bare clone that shares UPSTREAM_CLONE's objects (any clone holding upstream TensorFold history),
fetches every ref of the bundle into refs/restored/, and compares each restored sha with the bundle's own list and,
when given, with REFS.txt. Then runs a connectivity check over the restored refs. Exit 0 only if all agree.
"""
import os
import shutil
import subprocess
import sys
import tempfile

bundle, upstream = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
want_file = sys.argv[3] if len(sys.argv) > 3 else None


def git(cwd, *a, check=True):
    r = subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(a)}: {r.stderr[:800]}")
    return r.stdout


heads = [line.split(" ", 1) for line in git(upstream, "bundle", "list-heads", bundle).splitlines() if line]
tmp = tempfile.mkdtemp(prefix="bundle-restore-")
try:
    repo = os.path.join(tmp, "r.git")
    git(tmp, "clone", "-q", "--bare", "--shared", upstream, repo)
    git(repo, "fetch", "-q", bundle, "refs/*:refs/restored/*")
    bad = 0
    for sha, ref in heads:
        got = git(repo, "rev-parse", "refs/restored/" + ref[len("refs/"):], check=False).strip()
        if got != sha:
            bad += 1
            print(f"MISMATCH {ref}: bundle {sha[:12]} restored {got[:12]}")
    if want_file:
        want = dict(reversed(line.split(" ", 1)) for line in open(want_file).read().splitlines() if line)
        have = {ref: sha for sha, ref in heads}
        if want != have:
            bad += 1
            print(f"REFS.txt differs from the bundle: {len(want)} listed, {len(have)} in the bundle")
    fsck = subprocess.run(["git", "fsck", "--connectivity-only", *["refs/restored/" + r[len("refs/"):] for _, r in heads]], cwd=repo, capture_output=True, text=True)
    broken = [x for x in (fsck.stdout + fsck.stderr).splitlines() if "missing" in x or "broken" in x]
    print(f"verify_bundle: {len(heads)} refs, {bad} mismatches, connectivity {'ok' if not broken else 'BROKEN: ' + broken[0]}")
    sys.exit(1 if bad or broken else 0)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
