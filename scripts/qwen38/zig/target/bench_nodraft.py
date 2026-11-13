#!/usr/bin/env python3
"""tools/bench_concurrent.py with "draft": false on every request: its cells measured with the drafter off.

Upstream's bench_concurrent.stream() takes draft=False (what its --serial runs send), but its concurrent cells always
draft. This runs the same main() with every request sending "draft": false; the arguments, the printed cells and the
--output report are bench_concurrent.py's. The tools are imported from ./up-tools (upstream tools/ at the PR's base)
or from $UP_TOOLS.

  python3 bench_nodraft.py http://127.0.0.1:8080 MODEL --levels 1,2,4 --alone --serial --output off.json
"""

import inspect
import os
import sys

sys.path.insert(0, os.environ.get("UP_TOOLS") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "up-tools"))
import bench_concurrent  # noqa: E402

drafted_stream = bench_concurrent.stream
DRAFT_ARG = list(inspect.signature(drafted_stream).parameters).index("draft")


def plain_stream(*args, **kwargs):
    if len(args) > DRAFT_ARG:
        args = args[:DRAFT_ARG] + (False,) + args[DRAFT_ARG + 1:]
    else:
        kwargs["draft"] = False
    return drafted_stream(*args, **kwargs)


bench_concurrent.stream = plain_stream

if __name__ == "__main__":
    bench_concurrent.main()
