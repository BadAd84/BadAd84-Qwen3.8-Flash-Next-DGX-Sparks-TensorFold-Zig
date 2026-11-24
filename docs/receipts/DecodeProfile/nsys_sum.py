#!/usr/bin/env python3
"""nsys_sum.py REPORT.nsys-rep

Summarise an nsys CUDA trace into kernel and memcpy tables, by TOTAL device time, so a decode
window's kernel arrangement can be compared between two engines.

The report is a sqlite file: nsys writes it directly and this reads CUPTI's own tables -
CUPTI_ACTIVITY_KIND_KERNEL, _MEMCPY, _MEMSET, _SYNCHRONIZATION - joining StringIds for the names.
The tables present depend on the nsys version and on what CUPTI managed to record; the script prints
which are missing rather than inventing numbers.

Output, one block a family:
  KERNEL    total_ms  count  mean_us  name
  MEMCPY    total_ms  count  mean_us  NAME/kind
  MEMSET    total_ms  count  mean_us
  SYNC      total_ms  count  mean_us  kind
plus a TOTAL line and a NA line listing tables absent from this report.
"""
import sqlite3
import sys


def q(db, sql, args=()):
    return db.execute(sql, args).fetchall()


def has(db, table):
    r = db.execute("select 1 from sqlite_master where type='table' and name=?", (table,)).fetchone()
    return r is not None


def main():
    if len(sys.argv) < 2:
        print("usage: nsys_sum.py REPORT.nsys-rep", file=sys.stderr)
        return 2
    rep = sys.argv[1]
    db = sqlite3.connect(rep)
    missing = []
    grand = 0.0

    # ---- kernels ------------------------------------------------------------------------------
    if has(db, "CUPTI_ACTIVITY_KIND_KERNEL"):
        rows = q(db, """
            select (k.end - k.start) as dur, s.value as name
            from CUPTI_ACTIVITY_KIND_KERNEL k
            join StringIds s on s.id = k.shortName
        """)
        agg = {}
        for dur, name in rows:
            a = agg.setdefault(name, [0.0, 0])
            a[0] += dur
            a[1] += 1
        tot = sum(v[0] for v in agg.values()) / 1e6
        grand += tot
        print("KERNEL total %.3f ms, %d names, %d instances" % (tot, len(agg), sum(v[1] for v in agg.values())))
        for name, (dur, n) in sorted(agg.items(), key=lambda kv: -kv[1][0]):
            ms = dur / 1e6
            print("  %9.3f ms  x%5d  %8.2f us  %s" % (ms, n, ms * 1000.0 / max(1, n), name))
    else:
        missing.append("CUPTI_ACTIVITY_KIND_KERNEL")

    # ---- memcpy -------------------------------------------------------------------------------
    if has(db, "CUPTI_ACTIVITY_KIND_MEMCPY"):
        rows = q(db, "select (end - start), copyKind, bytes from CUPTI_ACTIVITY_KIND_MEMCPY")
        if rows:
            tot = sum(r[0] for r in rows) / 1e6
            bysz = sum(r[2] for r in rows)
            grand += tot
            kinds = {"1": "HtoD", "2": "DtoH", "3": "DtoD", "4": "HtoA", "5": "AtoH", "6": "AtoA",
                     "7": "AtoD", "8": "DtoA", "9": "DtoD_host", "10": "HtoH"}
            agg = {}
            for dur, kind, nb in rows:
                k = kinds.get(str(kind), str(kind))
                a = agg.setdefault(k, [0.0, 0, 0])
                a[0] += dur
                a[1] += 1
                a[2] += nb
            print("MEMCPY total %.3f ms, %d copies, %.1f MiB moved" % (tot, len(rows), bysz / 1048576.0))
            for k, (dur, n, nb) in sorted(agg.items(), key=lambda kv: -kv[1][0]):
                print("  %9.3f ms  x%5d  %8.2f us  %s  (%.1f MiB)" % (dur / 1e6, n, dur / 1e6 * 1000.0 / max(1, n), k, nb / 1048576.0))
    else:
        missing.append("CUPTI_ACTIVITY_KIND_MEMCPY")

    # ---- memset -------------------------------------------------------------------------------
    if has(db, "CUPTI_ACTIVITY_KIND_MEMSET"):
        rows = q(db, "select (end - start), bytes from CUPTI_ACTIVITY_KIND_MEMSET")
        if rows:
            tot = sum(r[0] for r in rows) / 1e6
            grand += tot
            print("MEMSET total %.3f ms, %d calls, %.1f MiB" % (tot, len(rows), sum(r[1] for r in rows) / 1048576.0))
    else:
        missing.append("CUPTI_ACTIVITY_KIND_MEMSET")

    # ---- sync ---------------------------------------------------------------------------------
    if has(db, "CUPTI_ACTIVITY_KIND_SYNCHRONIZATION"):
        rows = q(db, "select (end - start), syncType from CUPTI_ACTIVITY_KIND_SYNCHRONIZATION")
        if rows:
            tot = sum(r[0] for r in rows) / 1e6
            agg = {}
            for dur, kind in rows:
                a = agg.setdefault(str(kind), [0.0, 0])
                a[0] += dur
                a[1] += 1
            print("SYNC total %.3f ms, %d waits" % (tot, len(rows)))
            for k, (dur, n) in sorted(agg.items(), key=lambda kv: -kv[1][0]):
                print("  %9.3f ms  x%5d  %8.2f us  type %s" % (dur / 1e6, n, dur / 1e6 * 1000.0 / max(1, n), k))
    else:
        missing.append("CUPTI_ACTIVITY_KIND_SYNCHRONIZATION")

    print("TOTAL %.3f ms of device work in this report" % grand)
    if missing:
        print("NA tables absent from this report: %s" % ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
