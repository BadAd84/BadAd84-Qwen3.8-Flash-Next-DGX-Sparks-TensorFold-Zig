#!/usr/bin/env python3
"""nsum.py DB [t0_frac t1_frac]: kernel time by name over a window of the trace (fractions of the kernel span),
plus GPU busy share and gap total. Window defaults to the whole trace."""
import sqlite3, sys, collections
db = sys.argv[1]
c = sqlite3.connect(db)
tabs = {r[0] for r in c.execute("select name from sqlite_master where type='table'")}
if "CUPTI_ACTIVITY_KIND_KERNEL" not in tabs:
    print("no kernel table; tables:", sorted(tabs)); sys.exit(1)
rows = c.execute("select k.start, k.end, s.value, k.gridX*k.gridY*k.gridZ, k.blockX*k.blockY*k.blockZ "
                 "from CUPTI_ACTIVITY_KIND_KERNEL k join StringIds s on s.id = k.shortName order by k.start").fetchall()
t0, t1 = rows[0][0], rows[-1][1]
a = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
b = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
lo, hi = t0 + (t1 - t0) * a, t0 + (t1 - t0) * b
rows = [r for r in rows if r[0] >= lo and r[1] <= hi]
span = rows[-1][1] - rows[0][0]
tot = collections.Counter(); cnt = collections.Counter()
busy = 0; end = 0; gaps = 0
for s, e, n, g, bl in rows:
    tot[n] += e - s; cnt[n] += 1
    if s > end and end: gaps += s - end
    busy += max(0, e - max(s, end)); end = max(end, e)
print(f"kernels {len(rows)} span {span/1e6:.1f} ms busy {busy/span*100:.1f}% gaps {gaps/1e6:.1f} ms")
for n, t in tot.most_common(45):
    print(f"{t/1e6:9.2f} ms {t/span*100:5.1f}%  n={cnt[n]:6d} avg {t/cnt[n]/1e3:8.1f} us  {n[:90]}")
