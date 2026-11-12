#!/usr/bin/env python3
"""resolve_0010.py TREE - patch 0010 (a shared round priced from the environment) on v1.2.7: the lane core.

v1.2.7 changed the same pricing code (bb267e639): a learned row cost may fall below the table (`rowTerm`), and a
learning round reaches a least row count (`least_rows`). Our patch prices the forward by the streams' rows plus a
draft row's ms (`draft_row_ms`, `streams`, `rateRows`). Both stay: the head cost carries all four fields, a
candidate is rated by `rateRows` over upstream's `rowTerm` overhead and under upstream's `least` guard, and both
sides' tests are kept. With no draft row price, `rateRows` is `rate`, so the result is v1.2.7's own.
"""
import io
import re
import sys

tree = sys.argv[1].rstrip("/\\")


def resolve(path: str, picks: list) -> None:
    p = f"{tree}/{path}"
    s = io.open(p, encoding="utf-8", newline="").read()
    eol = "\r\n" if "\r\n" in s else "\n"
    s = s.replace("\r\n", "\n")
    blocks = re.findall(r"<<<<<<< ours\n(.*?)=======\n(.*?)>>>>>>> theirs\n", s, re.S)
    assert len(blocks) == len(picks), f"{path}: {len(blocks)} conflicts, {len(picks)} resolutions"
    it = iter(zip(blocks, picks))

    def sub(_m):
        (ours, theirs), pick = next(it)
        out = pick(ours, theirs)
        assert out is not None
        return out

    s = re.sub(r"<<<<<<< ours\n.*?=======\n.*?>>>>>>> theirs\n", sub, s, flags=re.S)
    assert "<<<<<<<" not in s and ">>>>>>>" not in s
    io.open(p, "w", encoding="utf-8", newline="").write(s.replace("\n", eol))


def fields(ours: str, theirs: str) -> str:
    assert "least_rows: u64 = 0" in ours and "draft_row_ms: f64 = 0.0" in theirs and "streams: u64 = 0" in theirs
    keep = [line for line in theirs.split("\n") if line and not line.lstrip().startswith("row_ms:")]
    return ours + "\n".join(keep) + "\n"


def first(ours: str, theirs: str) -> str:
    assert "const least = @min(head.least_rows, max_rows);" in ours and "const base = if (head.streams > 0)" in theirs
    base = [line for line in theirs.split("\n") if "const base" in line][0]
    return (
        "    const least = @min(head.least_rows, max_rows);\n" + base + "\n"
        "    var best = if (rows >= least) rateRows(costs, timed, base, rows, expected, overhead_ms + rowTerm(costs, timed, head, rows, live), head.draft_row_ms) else -std.math.inf(f64);\n"
    )


def step(ours: str, theirs: str) -> str:
    assert "if (rows < least) continue;" in ours and "rateRows(" in theirs and "head.step_ms * steps" in theirs
    return (
        "        if (rows < least) continue;\n"
        "        const now = rateRows(costs, timed, base, rows, expected, overhead_ms + head.step_ms * steps + rowTerm(costs, timed, head, rows, live), head.draft_row_ms);\n"
    )


def both_fns(ours: str, theirs: str) -> str:
    assert "pub fn rowTerm(" in ours and "fn rateRows(" in theirs
    return ours + "}\n\n" + theirs


def both_tests(ours: str, theirs: str) -> str:
    assert ours.count("\ntest ") + ours.startswith("test ") == 2 and theirs.startswith("test ")
    return ours + "}\n\n" + theirs


def call(ours: str, theirs: str) -> str:
    comment = [line for line in theirs.split("\n") if line.lstrip().startswith("//")]
    line = [line for line in ours.split("\n") if "alloc.allocateDrafts(" in line]
    assert len(line) == 1 and ".least_rows = " in line[0] and ".draft_row_ms = if (explicit or live) 0.0 else e.rule.k.draft_row_ms, .streams = plans.len" in theirs
    tail = " });"
    assert line[0].endswith(tail)
    return "\n".join(comment) + "\n" + line[0][: -len(tail)] + ", .draft_row_ms = if (explicit or live) 0.0 else e.rule.k.draft_row_ms, .streams = plans.len });\n"


resolve("zig/src/core/lanes/allocate.zig", [fields, first, step, both_fns, both_tests])
resolve("zig/src/core/lanes/windows.zig", [call])
print("resolve_0010: allocate.zig and windows.zig resolved (upstream's rowTerm and least rows, with our draft row price)")
