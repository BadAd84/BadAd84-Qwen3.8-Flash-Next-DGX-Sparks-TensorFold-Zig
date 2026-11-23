#!/usr/bin/env python3
"""rec.py OUT.json K=V...: write a JSON object; V is read as int, float or string."""
import json
import sys

out = {}
for arg in sys.argv[2:]:
    k, _, v = arg.partition("=")
    if v.isdigit() or (v.startswith("-") and v[1:].isdigit()):
        out[k] = int(v)
    else:
        try:
            out[k] = float(v)
        except ValueError:
            out[k] = v
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(out, f, indent=1, sort_keys=True)
    f.write("\n")
