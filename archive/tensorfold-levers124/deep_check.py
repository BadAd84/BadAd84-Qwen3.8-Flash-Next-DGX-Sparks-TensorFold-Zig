#!/usr/bin/env python3
"""deep_check.py BUNDLE UPSTREAM_CLONE [REF_SUBSTR] - are ALL objects (blobs too) of the bundle's refs present?

Restores the bundle into a throwaway clone sharing UPSTREAM_CLONE's objects, then walks every restored ref with
`rev-list --objects --missing=print` and counts objects that are missing. A partial upstream clone shows up as
missing upstream objects; anything missing that the bundle should carry is a hole in the bundle.
"""
import os
import shutil
import subprocess
import sys
import tempfile

bundle, upstream = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
only = sys.argv[3] if len(sys.argv) > 3 else ""


def git(cwd, *a):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True)


print("upstream clone partial:", git(upstream, "config", "--get-regexp", r"(promisor|partialclone)").stdout.strip() or "no")
tmp = tempfile.mkdtemp(prefix="deep-")
try:
    repo = os.path.join(tmp, "r.git")
    r = git(tmp, "clone", "-q", "--bare", "--shared", upstream, repo)
    assert r.returncode == 0, r.stderr
    git(repo, "config", "--unset-all", "remote.origin.promisor")
    r = git(repo, "fetch", "-q", bundle, "refs/*:refs/restored/*")
    assert r.returncode == 0, r.stderr
    refs = [x for x in git(repo, "for-each-ref", "--format=%(refname)", "refs/restored").stdout.split() if only in x]
    env = {**os.environ, "GIT_NO_LAZY_FETCH": "1"}
    p = subprocess.run(["git", "rev-list", "--objects", "--missing=print", *refs], cwd=repo, capture_output=True, text=True, env=env)
    lines = p.stdout.splitlines()
    missing = [x for x in lines if x.startswith("?")]
    print(f"deep_check: {len(refs)} refs, {len(lines) - len(missing)} objects walked, {len(missing)} missing (rc {p.returncode}) {p.stderr.strip()[:300]}")
    for m in missing[:5]:
        print("  missing", m)
    sys.exit(1 if missing or p.returncode else 0)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
