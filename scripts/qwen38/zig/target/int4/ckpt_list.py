"""ckpt_list.py SNAPSHOT_DIR [PATTERN...] - every tensor whose name contains a pattern: name, dtype, shape (headers only)."""
import json
import os
import struct
import sys

snap = sys.argv[1]
pats = sys.argv[2:] or ["layers.0.", "layers.3.", "mtp.", "lm_head", "embed_tokens", "hyper_connection_mixer", "norm."]
idx = json.load(open(os.path.join(snap, "model.safetensors.index.json")))["weight_map"]
headers = {}
for name, shard in sorted(idx.items()):
    if not any(p in name for p in pats):
        continue
    if ".experts." in name and ".experts.0." not in name and ".experts.511." not in name:
        continue
    if shard not in headers:
        with open(os.path.join(snap, shard), "rb") as f:
            n = struct.unpack("<Q", f.read(8))[0]
            headers[shard] = json.loads(f.read(n))
    h = headers[shard][name]
    print(f"{name}\t{h['dtype']}\t{h['shape']}")
