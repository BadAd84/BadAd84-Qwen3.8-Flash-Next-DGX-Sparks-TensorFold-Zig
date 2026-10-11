#!/usr/bin/env bash
# mutants.sh (spark6, no GPU): patches/0025's host tests and a mutant each, judged by exit code. hostmut4.py runs the
# unmutated tree first (both suites must pass), then each mutant on a git-archive copy of the stack (tf branch b4):
# `zig build test` or zig/tests/server/zig_test.sh must fail with the named test among the failures; it exits 0 only
# when every mutant is killed.
set -uo pipefail
cd ~/work/lanes/b4-pack || exit 1
python3 hostmut4.py retime-slow-raises-price retime-never-runs retime-runs-at-zero retime-two-ranks-stop-early \
  retime-cap-off-by-one
