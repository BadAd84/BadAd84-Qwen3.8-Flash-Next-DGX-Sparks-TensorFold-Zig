#!/usr/bin/env python3
"""nbusy.py DB [t0_frac t1_frac]: GPU busy share over a window, counting eager kernels and whole graph executions
(cuda-graph-trace=graph), and the idle gaps by size."""
import sqlite3, sys, collections
c = sqlite3.connect(sys.argv[1])
iv = [(s, e, "k") for s, e in c.execute("select start, end from CUPTI_ACTIVITY_KIND_KERNEL")]
iv += [(s, e, "g") for s, e in c.execute("select start, end from CUPTI_ACTIVITY_KIND_GRAPH_TRACE")]
iv.sort()
t0, t1 = iv[0][0], max(e for _, e, _ in iv)
a = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
b = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
lo, hi = t0 + (t1 - t0) * a, t0 + (t1 - t0) * b
iv = [x for x in iv if x[0] >= lo and x[1] <= hi]
busy = 0; end = iv[0][0]; gaps = collections.Counter(); gt = collections.Counter(); kind = collections.Counter()
for s, e, k in iv:
    if s > end:
        g = s - end
        bkt = "<5us" if g < 5e3 else "<20us" if g < 2e4 else "<100us" if g < 1e5 else "<1ms" if g < 1e6 else ">=1ms"
        gaps[bkt] += 1; gt[bkt] += g
    busy += max(0, e - max(s, end)); kind[k] += max(0, e - max(s, end)); end = max(end, e)
span = end - iv[0][0]
print(f"span {span/1e6:.1f} ms busy {busy/span*100:.1f}% (graphs {kind['g']/span*100:.1f}%, kernels {kind['k']/span*100:.1f}%)")
for bkt in ("<5us", "<20us", "<100us", "<1ms", ">=1ms"):
    print(f"  gaps {bkt:7s} n={gaps[bkt]:7d} total {gt[bkt]/1e6:8.1f} ms ({gt[bkt]/span*100:.1f}%)")
