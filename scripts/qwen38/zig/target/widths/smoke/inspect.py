#!/usr/bin/env python3
"""inspect.py SNAPSHOT - the FP4-Local checkpoint's routing and shared-expert facts: config fields, and for layer 0
and the MTP layer each shared-expert tensor's file, dtype and shape (from the safetensors headers)."""
import json
import struct
import sys
from pathlib import Path

s = Path(sys.argv[1])
c = json.loads((s / "config.json").read_text())
t = c.get("text_config", c)
print({k: t.get(k) for k in ("num_experts_per_tok", "shared_expert_intermediate_size", "moe_intermediate_size",
                             "num_experts", "hidden_size", "num_hidden_layers", "mtp_num_hidden_layers")})
print("quant:", json.dumps(c.get("quantization_config", t.get("quantization_config")))[:600])
idx = json.loads((s / "model.safetensors.index.json").read_text())["weight_map"]
files = sorted(set(idx.values()))
print("files", len(files), files[:3])
want = [k for k in idx if (".layers.0.mlp.shared_expert" in k and "language_model" in k) or k.startswith("mtp.layers.0.mlp.shared_expert")]


def header(p):
    with open(p, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        return json.loads(f.read(n))


cache = {}
for k in sorted(want):
    f = idx[k]
    if f not in cache:
        cache[f] = header(s / f)
    h = cache[f][k]
    print(k, f, h["dtype"], h["shape"])
