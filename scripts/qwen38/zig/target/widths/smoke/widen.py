#!/usr/bin/env python3
"""widen.py SNAPSHOT OUT - a top-5 checkpoint with a 1280-wide shared expert built from the FP4-Local snapshot, for a
device smoke of the widths step. Every file of SNAPSHOT is hard-linked into OUT except three: config.json (its text
config's num_experts_per_tok 5 and shared_expert_intermediate_size 1280), the index (each main layer's shared-expert
tensors mapped to one new shard) and that shard, where each main layer's shared gate_proj and up_proj gain 640 zero
rows and down_proj 640 zero input columns (FP8 zero bytes, block scales 127, that is 1.0). The added units are zero,
so the shared expert's output equals the 640-wide one's; the MTP layer's shared expert stays 640 wide."""
import json
import os
import struct
import sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
ADD = 640
NEW = "tensors/model-widths-smoke.safetensors"


def header(path):
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        return json.loads(f.read(n)), 8 + n


def read(path, meta, base):
    a, b = meta["data_offsets"]
    with open(path, "rb") as f:
        f.seek(base + a)
        return f.read(b - a)


def pad_rows(data, shape, width, fill):
    return data + bytes([fill]) * (ADD * shape[1] * width), [shape[0] + ADD, shape[1]]


def pad_cols(data, shape, width, cols, fill):
    row = shape[1] * width
    extra = bytes([fill]) * (cols * width)
    return b"".join(data[r * row:(r + 1) * row] + extra for r in range(shape[0])), [shape[0], shape[1] + cols]


for root, _dirs, files in os.walk(src):
    rel = Path(root).relative_to(src)
    (out / rel).mkdir(parents=True, exist_ok=True)
    for name in files:
        if rel == Path(".") and name in ("config.json", "model.safetensors.index.json"):
            continue
        dst = out / rel / name
        if not dst.exists():
            os.link(os.path.realpath(Path(root) / name), dst)

cfg = json.loads((src / "config.json").read_text())
text = cfg.get("text_config", cfg)
assert text["num_experts_per_tok"] == 10 and text["shared_expert_intermediate_size"] == 640, text
text["num_experts_per_tok"] = 5
text["shared_expert_intermediate_size"] = 640 + ADD
(out / "config.json").write_text(json.dumps(cfg, indent=2))

index = json.loads((src / "model.safetensors.index.json").read_text())
wm = index["weight_map"]
layers = text["num_hidden_layers"]
headers = {}
tensors = {}
for layer in range(layers):
    for proj in ("gate_proj", "up_proj", "down_proj"):
        for part in ("weight", "weight_scale"):
            key = f"model.language_model.layers.{layer}.mlp.shared_expert.{proj}.{part}"
            shard = wm[key]
            if shard not in headers:
                headers[shard] = header(src / shard)
            h, base = headers[shard]
            meta = h[key]
            data = read(src / shard, meta, base)
            dtype, shape = meta["dtype"], meta["shape"]
            width = {"F8_E4M3": 1, "U8": 1, "BF16": 2}[dtype]
            fill = 127 if part == "weight_scale" else 0
            if proj != "down_proj":
                data, shape = pad_rows(data, shape, width, fill)
            else:
                cols = ADD if part == "weight" else ADD * shape[1] // 640
                data, shape = pad_cols(data, shape, width, cols, fill)
            tensors[key] = (dtype, shape, data)
            wm[key] = NEW

meta, offset, blobs = {}, 0, []
for key in sorted(tensors):
    dtype, shape, data = tensors[key]
    meta[key] = {"dtype": dtype, "shape": shape, "data_offsets": [offset, offset + len(data)]}
    offset += len(data)
    blobs.append(data)
head = json.dumps(meta, separators=(",", ":")).encode()
head += b" " * (-len(head) % 8)
with open(out / NEW, "wb") as f:
    f.write(struct.pack("<Q", len(head)))
    f.write(head)
    for b in blobs:
        f.write(b)
(out / "model.safetensors.index.json").write_text(json.dumps(index))
print(f"widened {len(tensors)} tensors over {layers} layers into {NEW} ({offset} bytes); config top-k 5, shared 1280")
