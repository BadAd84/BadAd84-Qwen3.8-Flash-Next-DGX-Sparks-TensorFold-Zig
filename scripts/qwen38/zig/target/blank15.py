"""blank15.py OUT - every reply hash of each receipt0015 arm against M1's: the same request, the same seed, in order."""
import json
import os
import sys

OUT = sys.argv[1]
FILES = ["conc_t0", "conc_t1_s1234", "conc_t1_s2234", "conc_t1_s3234"]


def hashes(node, out):
    """Every token_sha256 under `node` in document order (the alone and serial replies a cell checks)."""
    if isinstance(node, dict):
        if isinstance(node.get("token_sha256"), str):
            out.append(node["token_sha256"])
        for v in node.values():
            hashes(v, out)
    elif isinstance(node, list):
        for v in node:
            hashes(v, out)
    return out


def arm(name):
    return [hashes(json.load(open(os.path.join(OUT, name, f + ".json"))), []) for f in FILES]


base = arm("M1")
for name in ["M2", "U1", "U2", "X1", "X2"]:
    if not os.path.isdir(os.path.join(OUT, name)):
        continue
    got = arm(name)
    equal = sum(a == b for x, y in zip(base, got) for a, b in zip(x, y))
    total = sum(len(x) for x in base)
    print(f"{name} against M1: {equal} of {total} reply hashes equal ({', '.join(str(len(x)) for x in got)} a file)")
