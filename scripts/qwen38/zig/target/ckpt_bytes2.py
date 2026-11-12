#!/usr/bin/env python3
"""ckpt_bytes2.py DIR [DIR ...] - bytes by tensor group of the safetensors checkpoints under each DIR, from the
file headers only (no tensor data is read). Groups: routed experts, shared experts, n-gram tables, embeddings and
head, mtp.*, hyper-connection (hc) matrices, and the rest (the mixers and dense projections), with the dtypes seen."""
import glob
import json
import os
import re
import struct
import sys
from collections import defaultdict

SIZES = {"BF16": 2, "F16": 2, "F32": 4, "F64": 8, "I8": 1, "U8": 1, "I16": 2, "U16": 2, "I32": 4, "U32": 4, "I64": 8,
         "U64": 8, "F8_E4M3": 1, "F8_E5M2": 1, "BOOL": 1}


def group(name: str) -> str:
    n = name
    mtp = n.startswith("mtp.") or ".mtp." in n
    pre = "mtp:" if mtp else ""
    if re.search(r"(^|\.)ngram|n_gram|\.ple\b|embed_ngram|per_layer|ple_", n):
        return pre + "ngram/ple"
    if re.search(r"experts\.\d+|\.experts\.|expert", n) and "shared" not in n:
        return pre + "routed experts"
    if "shared_expert" in n or "shared_experts" in n:
        return pre + "shared expert"
    if re.search(r"embed_tokens|lm_head|\.embed", n):
        return pre + "embed/head"
    if re.search(r"hc_|hyper|\.hc\b|_hc|hconn", n):
        return pre + "hyper-connection"
    return pre + "dense (mixers, projections, other)"


for d in sys.argv[1:]:
    tot = defaultdict(int)
    dt = defaultdict(set)
    files = sorted(glob.glob(os.path.join(d, "**", "*.safetensors"), recursive=True))
    for f in files:
        with open(f, "rb") as fh:
            (n,) = struct.unpack("<Q", fh.read(8))
            h = json.loads(fh.read(n))
        for k, v in h.items():
            if k == "__metadata__":
                continue
            sz = SIZES.get(v["dtype"], 1)
            for s in v["shape"]:
                sz *= s
            g = group(k)
            tot[g] += sz
            dt[g].add(v["dtype"])
    print(f"== {d}: {len(files)} files, {sum(tot.values()) / 1e9:.2f} GB")
    for g, b in sorted(tot.items(), key=lambda kv: -kv[1]):
        print(f"  {g:42s} {b / 1e6:10.1f} MB  {','.join(sorted(dt[g]))}")
