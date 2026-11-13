#!/usr/bin/env python3
"""kall.py LOG - every row of the kernel log's decode window, a round, sorted by time.

The decode window is the log's last table (a trailing request closes it); its rounds are the server's `done` lines
between the table before it and it (rtab.py's window). Prints ms a round, launches a round, us a launch, grid and
symbol for every row.
"""
import re
import sys

HEAD = re.compile(r"^kernel log: window ([\d.]+) ms wall, ([\d.]+) ms in kernels, (\d+) launches")
ROW = re.compile(r"^kernel log: ([\d.]+) ms (\d+) launches ([\d.]+) us each grid (\d+) (.*)$")
DONE = re.compile(r"done chatcmpl-\S+ .* rounds=(\d+)")


def main():
    path = sys.argv[1]
    gap, rounds, rows, head = 0, 0, [], (0.0, 0.0, 0)
    for line in open(path, errors="replace"):
        m = HEAD.match(line)
        if m:
            rounds, gap, rows = gap, 0, []
            head = (float(m.group(1)), float(m.group(2)), int(m.group(3)))
            continue
        m = ROW.match(line)
        if m:
            rows.append((float(m.group(1)), int(m.group(2)), float(m.group(3)), int(m.group(4)), m.group(5).strip()))
            continue
        m = DONE.search(line)
        if m:
            gap += int(m.group(1))
    R = max(rounds, 1)
    wall, kern, launches = head
    print(f"== {path}: rounds {rounds}, window {wall / R:.2f} ms wall, {kern / R:.2f} ms in kernels, "
          f"{launches / R:.1f} launches a round; {len(rows)} rows")
    for ms, n, us, grid, sym in sorted(rows, key=lambda r: -r[0]):
        print(f"{ms / R:7.3f} ms {n / R:7.2f}/round {us:8.1f} us grid {grid:6d} {sym}")


if __name__ == "__main__":
    main()
