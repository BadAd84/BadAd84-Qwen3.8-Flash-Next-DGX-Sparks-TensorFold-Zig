#!/usr/bin/env python3
"""smokesum.py RUN_DIR - smoke.sh's results: the branch's boot and widths lines, bench_concurrent alone/serial counts,
served_exactness drafts, bench_openai tok/s, accepted per round, the sample reply, and main's refusal."""
import json
import re
import sys
from pathlib import Path

R = Path(sys.argv[1])
print((R / "run.log").read_text())
b = R / "branch"
srv = (b / "server.log").read_text(errors="replace") if (b / "server.log").exists() else ""
for pat in ("num_experts_per_tok", "shared_expert", "top-5", "1280", "error", "refus"):
    for line in sorted({ln.strip()[:200] for ln in srv.splitlines() if pat in ln})[:3]:
        print(f"server[{pat}]: {line}")
try:
    conc = json.loads((b / "conc.json").read_text())
    for c in conc["cells"]:
        print(f"conc {c['prompt']} x{c['streams']}: per-stream {c['per_stream_tps']} tok/s, alone {c.get('alone')}, "
              f"serial {c.get('serial')}, failed {c['failed']}")
except (OSError, ValueError, KeyError) as e:
    print("conc missing", e)
try:
    rows = json.loads((b / "drafts.json").read_text())["rows"]
    print(f"drafts: {sum(1 for x in rows if x['equal'])}/{len(rows)} equal (drafted against draft:false), accepted "
          f"{[x['drafted']['accepted'] for x in rows]}")
except (OSError, ValueError, KeyError) as e:
    print("drafts missing", e)
try:
    for r in json.loads((b / "openai.json").read_text()):
        print(f"openai {r['prompt']}: {r['decode_tps_median']:.2f} tok/s median of {r['decode_tps_all']}")
except (OSError, ValueError, KeyError) as e:
    print("openai missing", e)
m = {}
for line in (b / "metrics.txt").read_text().splitlines() if (b / "metrics.txt").exists() else []:
    name, *rest = line.split()
    m[name] = dict(zip(rest[0::2], map(float, rest[1::2])))
for a, z in (("before", "after_conc"), ("after_conc", "after_openai")):
    if a in m and z in m:
        d = {k.split(":")[-1]: m[z][k] - m[a].get(k, 0) for k in m[z]}
        r = d.get("decode_rounds_total", 0)
        print(f"{z}: accepted {int(d.get('mtp_accepted_total', 0))} of {int(d.get('mtp_drafted_total', 0))} drafted over "
              f"{int(r)} rounds ({d.get('mtp_accepted_total', 0) / r:.3f} a round)" if r else f"{z}: no rounds")
try:
    s = json.loads((b / "sample.json").read_text())
    print("sample:", re.sub(r"\s+", " ", s["choices"][0]["message"]["content"])[:400])
except (OSError, ValueError, KeyError, IndexError) as e:
    print("sample missing", e)
mn = R / "main"
for f in ("boot.log", "server.log"):
    p = mn / f
    if p.exists():
        for line in [ln for ln in p.read_text(errors="replace").splitlines() if re.search(r"num_experts_per_tok|error|ERROR", ln)][:4]:
            print(f"main {f}: {line.strip()[:220]}")
