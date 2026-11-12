#!/usr/bin/env python3
"""ckpt_layer.py DIR LAYER_SUBSTRING - every tensor whose name contains LAYER_SUBSTRING in the safetensors under DIR:
name, dtype, shape, MB (headers only)."""
import glob
import json
import os
import struct
import sys

SIZES = {"BF16": 2, "F16": 2, "F32": 4, "I8": 1, "U8": 1, "I32": 4, "I64": 8, "F8_E4M3": 1}
d, sub = sys.argv[1], sys.argv[2]
tot = {}
for f in sorted(glob.glob(os.path.join(d, "**", "*.safetensors"), recursive=True)):
    with open(f, "rb") as fh:
        (n,) = struct.unpack("<Q", fh.read(8))
        h = json.loads(fh.read(n))
    for k, v in h.items():
        if k == "__metadata__" or sub not in k:
            continue
        sz = SIZES.get(v["dtype"], 1)
        for s in v["shape"]:
            sz *= s
        print(f"{k:90s} {v['dtype']:8s} {str(v['shape']):22s} {sz / 1e6:9.3f}")
        tot[v["dtype"]] = tot.get(v["dtype"], 0) + sz
print({k: round(b / 1e6, 2) for k, b in tot.items()})
