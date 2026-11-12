#!/usr/bin/env python3
"""ckpt_bytes.py MODEL_DIR [LAYER] - what a decode round has to read: the checkpoint's tensors by layer part.

Reads only the safetensors headers. Prints, for one layer (default 1) and for the model, every tensor's shape, dtype
and bytes grouped by part (hyper-connection, mixer, experts, router, n-gram, head), so a kernel table's time can be
set against the bytes its kernels walk. A routed expert is read only when a row picks it: its bytes are listed one
expert at a time.
"""
from __future__ import annotations

import glob
import json
import os
import re
import struct
import sys
from collections import defaultdict

SIZES = {"BF16": 2, "F16": 2, "F32": 4, "F64": 8, "I8": 1, "U8": 1, "I16": 2, "U16": 2, "I32": 4, "U32": 4, "I64": 8, "U64": 8, "BOOL": 1}


def headers(d: str):
    for p in sorted(glob.glob(os.path.join(d, "**", "*.safetensors"), recursive=True)):
        with open(p, "rb") as f:
            n = struct.unpack("<Q", f.read(8))[0]
            h = json.loads(f.read(n))
        for name, t in h.items():
            if name != "__metadata__":
                yield os.path.basename(p), name, t["dtype"], t["shape"], t["data_offsets"][1] - t["data_offsets"][0]


def part(name: str) -> str:
    for key, label in (("hyper_connection", "hyper-connection"), ("hc_norm", "hyper-connection"), ("experts", "experts"), ("router", "router"), ("gate", "router"),
                       ("linear_attn", "mixer"), ("self_attn", "mixer"), ("attn", "mixer"), ("ngram", "n-gram"), ("ple", "n-gram"), ("lm_head", "head"), ("mtp", "mtp"), ("embed", "embed"), ("visual", "vision"), ("vision", "vision")):
        if key in name:
            return label
    return "other"


def main() -> None:
    d = sys.argv[1]
    layer = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    total = defaultdict(int)
    by_dtype = defaultdict(int)
    rows = []
    for _file, name, dtype, shape, nbytes in headers(d):
        p = part(name)
        total[p] += nbytes
        by_dtype[(p, dtype)] += nbytes
        m = re.search(r"layers\.(\d+)\.", name)
        e = re.search(r"experts\.(\d+)\.", name)
        if m and int(m.group(1)) == layer and "mtp" not in name and (e is None or e.group(1) == "0") and nbytes >= 1024 and "shard_" not in name:
            rows.append((p, name, dtype, shape, nbytes))
    print(f"== layer {layer}: every tensor of 1 KiB or more (one routed expert shown, the n-gram shards left out)")
    for p, name, dtype, shape, nbytes in sorted(rows):
        print(f"{p:17s} {nbytes / 1e6:10.3f} MB {dtype:5s} {str(shape):26s} {name}")
    print("== the model by part and dtype, GB")
    for (p, dtype), nbytes in sorted(by_dtype.items()):
        print(f"{p:17s} {dtype:5s} {nbytes / 1e9:9.3f}")
    print("== the model by part, GB")
    for p, nbytes in sorted(total.items(), key=lambda kv: -kv[1]):
        print(f"{p:17s} {nbytes / 1e9:9.3f}")
    print(f"all               {sum(total.values()) / 1e9:9.3f}")


if __name__ == "__main__":
    main()
