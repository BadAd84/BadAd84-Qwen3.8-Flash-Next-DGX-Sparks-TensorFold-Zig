#!/usr/bin/env python3
"""nseq.py DB at_frac ms: the kernel sequence for `ms` milliseconds from at_frac of the trace, runs of the same
kernel+grid collapsed (count, total us), with the gap before each run."""
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
t0, t1 = c.execute("select min(start), max(end) from CUPTI_ACTIVITY_KIND_KERNEL").fetchone()
lo = t0 + (t1 - t0) * float(sys.argv[2]); hi = lo + float(sys.argv[3]) * 1e6
rows = c.execute("select k.start, k.end, s.value, k.gridX, k.gridY, k.gridZ from CUPTI_ACTIVITY_KIND_KERNEL k "
                 "join StringIds s on s.id = k.shortName where k.start >= ? and k.start < ? order by k.start", (lo, hi)).fetchall()
runs = []; prev_end = None
for s, e, n, gx, gy, gz in rows:
    key = (n, gx, gy, gz); gap = (s - prev_end) if prev_end else 0
    if runs and runs[-1][0] == key: runs[-1][1] += 1; runs[-1][2] += e - s; runs[-1][3] += gap
    else: runs.append([key, 1, e - s, gap])
    prev_end = e
for (n, gx, gy, gz), k, t, gap in runs:
    print(f"{k:4d}x {t/1e3:9.1f} us gaps {gap/1e3:7.1f}  {n[:40]:40s} ({gx},{gy},{gz})")
