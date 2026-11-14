"""blank15.py OUT - every reply hash of each receipt0015 (or updraft.sh) arm against M1's: the same request, the same
seed, in order. A bench_concurrent reply counts its token_sha256, a bench_openai run its token_sha; a file M1 lacks is
skipped, and each file's count is printed so a subset (e.g. the conc_t* files alone) can be read off."""
import json
import os
import sys

OUT = sys.argv[1]
FILES = ["openai_t0", "openai_t1", "conc_t0", "conc_t1_s1234", "conc_t1_s2234", "conc_t1_s3234"]


def hashes(node, out):
    """Every reply hash under `node` in document order: token_sha256 where a reply carries that key, else token_sha."""
    if isinstance(node, dict):
        h = node["token_sha256"] if "token_sha256" in node else node.get("token_sha")
        if isinstance(h, str):
            out.append(h)
        for v in node.values():
            hashes(v, out)
    elif isinstance(node, list):
        for v in node:
            hashes(v, out)
    return out


def arm(name, files):
    return [hashes(json.load(open(os.path.join(OUT, name, f + ".json"))), []) for f in files]


files = [f for f in FILES if os.path.exists(os.path.join(OUT, "M1", f + ".json"))]
base = arm("M1", files)
for name in ["M2", "M3", "M4", "U1", "U2", "U3", "U4", "X1", "X2", "X3", "X4"]:
    have = [f for f in files if os.path.exists(os.path.join(OUT, name, f + ".json"))]
    if not have:
        continue
    got = dict(zip(have, arm(name, have)))
    per = [(f, sum(a == b for a, b in zip(x, got[f])), len(x)) for f, x in zip(files, base) if f in got]
    print(f"{name} against M1: {sum(e for _, e, _ in per)} of {sum(t for _, _, t in per)} reply hashes equal ("
          + ", ".join(f"{f} {e}/{t}" for f, e, t in per) + ")")
