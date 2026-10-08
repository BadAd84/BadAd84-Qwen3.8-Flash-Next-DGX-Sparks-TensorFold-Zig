#!/usr/bin/env python3
"""nshape.py DB NAME [t0_frac t1_frac]: one kernel's calls grouped by grid/block, time each."""
import sqlite3, sys, collections
c = sqlite3.connect(sys.argv[1]); name = sys.argv[2]
rows = c.execute("select k.start, k.end, k.gridX, k.gridY, k.gridZ, k.blockX, k.blockY, k.dynamicSharedMemory from "
                 "CUPTI_ACTIVITY_KIND_KERNEL k join StringIds s on s.id = k.shortName where s.value = ? order by k.start",
                 (name,)).fetchall()
allr = c.execute("select min(start), max(end) from CUPTI_ACTIVITY_KIND_KERNEL").fetchone()
a = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
b = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
lo, hi = allr[0] + (allr[1] - allr[0]) * a, allr[0] + (allr[1] - allr[0]) * b
rows = [r for r in rows if r[0] >= lo and r[1] <= hi]
g = collections.defaultdict(list)
for s, e, *k in rows: g[tuple(k)].append(e - s)
for k, v in sorted(g.items(), key=lambda kv: -sum(kv[1])):
    v.sort()
    print(f"{sum(v)/1e6:8.2f} ms n={len(v):6d} med {v[len(v)//2]/1e3:8.1f} us grid {k[:3]} block {k[3:5]} smem {k[5]}")
