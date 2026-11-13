"""st_head.py FILE [N] - a safetensors file's first N tensor names with dtype and shape (header only)."""
import json
import struct
import sys

with open(sys.argv[1], "rb") as f:
    n = struct.unpack("<Q", f.read(8))[0]
    h = json.loads(f.read(n))
items = [(k, v) for k, v in h.items() if k != "__metadata__"]
for k, v in items[: int(sys.argv[2]) if len(sys.argv) > 2 else 10]:
    print(k, v["dtype"], v["shape"])
print("tensors", len(items), "metadata", h.get("__metadata__"))
